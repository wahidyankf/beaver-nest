defmodule BnestAppWeb.ChatLive do
  use BnestAppWeb, :live_view

  alias BnestApp.Chat
  alias BnestApp.Codex.{ModelAccess, ModelCatalog, Settings}
  alias BnestApp.DataRepository

  @max_snapshot_bytes 500_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    models = ModelCatalog.all()
    model_access = ModelAccess.resolve(socket.assigns.current_user, models)
    {chat, central_record} = restore_chat(socket, model_access.model, model_access.models)

    chat =
      if model_access.selectable? do
        chat
      else
        Chat.enforce_model(chat, model_access.model.id, model_access.reasoning_effort)
      end

    chat = if model_access.available?, do: chat, else: Chat.fail(chat, model_access.error)

    socket =
      socket
      |> assign(:chat, chat)
      |> assign(:models, model_access.models)
      |> assign(:model_access, model_access)
      |> assign(:form, prompt_form())
      |> assign(:central_record, central_record)
      |> assign(:session_adapter, nil)
      |> assign(:codex_session, nil)
      |> assign(:checkpoint_timer, nil)

    if connected?(socket) and model_access.available?,
      do: connect_codex(socket, chat),
      else: {:ok, socket}
  end

  def handle_event("select_model", %{"model" => model_id}, socket) do
    models = Map.get(socket.assigns, :models, ModelCatalog.all())

    with true <- model_selection_allowed?(socket),
         false <- socket.assigns.chat.busy,
         %{} = model <- selected_model(models, model_id),
         reasoning_effort =
           ModelCatalog.reasoning_effort(model, socket.assigns.chat.reasoning_effort),
         {:ok, chat} <- Chat.select_model(socket.assigns.chat, model.id, reasoning_effort) do
      {:noreply, replace_codex(socket, chat)}
    else
      _busy_or_unknown -> {:noreply, socket}
    end
  end

  def handle_event("ignore_model_recovery", _params, socket), do: {:noreply, socket}

  def handle_event("select_effort", %{"reasoning_effort" => reasoning_effort}, socket) do
    models = Map.get(socket.assigns, :models, ModelCatalog.all())

    with true <- model_selection_allowed?(socket),
         false <- socket.assigns.chat.busy,
         %{} = model <- selected_model(models, socket.assigns.chat.model),
         true <- reasoning_effort in model.supported_reasoning_efforts,
         {:ok, chat} <-
           Chat.select_model(socket.assigns.chat, socket.assigns.chat.model, reasoning_effort) do
      {:noreply, replace_codex(socket, chat)}
    else
      _busy_or_unsupported -> {:noreply, socket}
    end
  end

  def handle_event("ignore_effort_recovery", _params, socket), do: {:noreply, socket}

  def handle_event("recover_draft", %{"chat" => %{"prompt" => prompt}}, socket) do
    {:noreply, assign(socket, :form, prompt_form(prompt))}
  end

  @impl Phoenix.LiveView
  def handle_event("send", _params, %{assigns: %{model_access: %{available?: false}}} = socket),
    do: {:noreply, socket}

  def handle_event("send", %{"chat" => %{"prompt" => prompt}}, socket) do
    case Chat.submit(socket.assigns.chat, prompt) do
      {:ok, chat} ->
        socket = socket |> assign(:chat, chat) |> assign(:form, prompt_form()) |> persist_chat()

        case socket.assigns.session_adapter.send_prompt(socket.assigns.codex_session, prompt) do
          :ok ->
            {:noreply, socket}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:chat, Chat.fail(chat, "Codex is not available."))
             |> persist_chat()}
        end

      {:error, chat} ->
        {:noreply, assign(socket, :chat, chat)}
    end
  end

  def handle_event("clear", _params, socket) do
    if socket.assigns.model_access.available? do
      clear_available_chat(socket)
    else
      {:noreply, socket}
    end
  end

  defp clear_available_chat(socket) do
    socket.assigns.session_adapter.close(socket.assigns.codex_session)

    socket =
      socket
      |> assign(
        :chat,
        Chat.new(socket.assigns.chat.model, socket.assigns.chat.reasoning_effort)
      )
      |> assign(:form, prompt_form())
      |> clear_chat_persistence()

    {:ok, socket} = connect_codex(socket, socket.assigns.chat)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:codex, session, {:thread_started, thread_id}},
        %{assigns: %{codex_session: session}} = socket
      ) do
    socket = socket |> update(:chat, &Chat.put_thread_id(&1, thread_id)) |> persist_chat()
    {:noreply, socket}
  end

  def handle_info(
        {:codex, session, {:assistant_update, text}},
        %{assigns: %{codex_session: session}} = socket
      ) do
    {:noreply,
     socket
     |> update(:chat, &Chat.update_assistant(&1, text))
     |> schedule_checkpoint()}
  end

  def handle_info(
        {:codex, session, :turn_completed},
        %{assigns: %{codex_session: session}} = socket
      ) do
    socket = update(socket, :chat, &Chat.complete/1)
    {:noreply, persist_chat(socket)}
  end

  def handle_info(
        {:codex, session, {:error, message}},
        %{assigns: %{codex_session: session}} = socket
      ) do
    {:noreply, socket |> update(:chat, &Chat.fail(&1, message)) |> persist_chat()}
  end

  def handle_info(
        {:codex, session, {:resume_failed, _message}},
        %{assigns: %{codex_session: session}} = socket
      ) do
    socket.assigns.session_adapter.close(session)

    fresh = %{
      Chat.fail(
        socket.assigns.chat,
        "The previous Codex conversation was unavailable. Your transcript is preserved in a fresh conversation."
      )
      | thread_id: nil
    }

    case socket.assigns.session_adapter.open(
           self(),
           nil,
           fresh.model,
           fresh.reasoning_effort
         ) do
      {:ok, replacement} ->
        socket = assign(socket, chat: fresh, codex_session: replacement)
        {:noreply, persist_chat(socket)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:chat, Chat.fail(fresh, "Codex is not available."))
         |> persist_chat()}
    end
  end

  def handle_info({:codex, _stale_session, _event}, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_info(:checkpoint_chat, socket) do
    {:noreply, socket |> assign(:checkpoint_timer, nil) |> persist_chat()}
  end

  @impl Phoenix.LiveView
  def terminate(_reason, %{assigns: %{session_adapter: nil}}), do: :ok

  def terminate(_reason, socket) do
    socket.assigns.session_adapter.close(socket.assigns.codex_session)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="chat-shell">
      <section class="chat-panel" aria-labelledby="chat-title">
        <header class="chat-header">
          <a href="/" class="brand-identity" aria-label="Beaver Nest home">
            <img
              class="brand-logo"
              data-role="brand-logo"
              src="/images/beaver-nest-logo.png"
              alt="Beaver Nest logo"
              width="52"
              height="52"
            />
            <div>
              <p class="chat-kicker">Local Codex chat</p>
              <h1 id="chat-title">Beaver Nest</h1>
            </div>
          </a>
          <div class="chat-actions">
            <form
              :if={@model_access.selectable?}
              id="model-picker"
              phx-change="select_model"
              phx-auto-recover="ignore_model_recovery"
              class="model-picker"
            >
              <label for="model-selector">Model</label>
              <select
                id="model-selector"
                name="model"
                data-role="model-selector"
                disabled={@chat.busy}
              >
                <option
                  :for={model <- @models}
                  value={model.id}
                  selected={model.id == @chat.model}
                >
                  {model.display_name}
                </option>
              </select>
            </form>
            <form
              :if={@model_access.selectable?}
              id="effort-picker"
              phx-change="select_effort"
              phx-auto-recover="ignore_effort_recovery"
              class="model-picker"
            >
              <label for="effort-selector">Reasoning effort</label>
              <select
                id="effort-selector"
                name="reasoning_effort"
                data-role="effort-selector"
                disabled={@chat.busy}
              >
                <option
                  :for={effort <- selected_model(@models, @chat.model).supported_reasoning_efforts}
                  value={effort}
                  selected={effort == @chat.reasoning_effort}
                >
                  {Settings.effort_label(effort)}
                </option>
              </select>
            </form>
            <span
              class="model-badge"
              data-model={@chat.model}
              data-reasoning-effort={@chat.reasoning_effort}
            >
              {Settings.label(model_display_name(@models, @chat.model), @chat.reasoning_effort)}
            </span>
            <nav class="chat-theme-control" aria-label="Color theme">
              <Layouts.theme_toggle />
            </nav>
            <button
              type="button"
              class="clear-chat-button"
              data-role="clear-chat"
              phx-click="clear"
            >
              Clear chat
            </button>
          </div>
        </header>

        <div class="conversation" aria-live="polite" aria-label="Conversation">
          <div :if={@chat.messages == []} class="empty-state">
            <p>Ask Codex about this repository.</p>
            <span>This conversation is saved to your account until you clear it.</span>
          </div>

          <article :for={message <- @chat.messages} class={message_class(message)} data-role="message">
            <p class="message-label">{if message.role == :visitor, do: "You", else: "Codex"}</p>
            <p
              :if={message.role == :visitor}
              class="message-content"
              data-role="user-message"
            >
              {message.content}
            </p>
            <p
              :if={message.role == :assistant}
              class="message-content whitespace-pre-wrap"
              data-role="assistant-message"
              data-streaming={to_string(message.streaming)}
              data-update-count={message.update_count}
            >
              {assistant_content(message)}
            </p>
          </article>
        </div>

        <p :if={@chat.error} class="chat-error" role="alert">{@chat.error}</p>

        <.form
          for={@form}
          id="chat-composer-form"
          phx-change="recover_draft"
          phx-auto-recover="recover_draft"
          phx-submit="send"
          class="composer"
        >
          <.input
            field={@form[:prompt]}
            type="textarea"
            label="Message"
            placeholder="Ask Codex…"
            rows="3"
            data-role="chat-composer"
            disabled={@chat.busy or not @model_access.available?}
            required
          />
          <button
            type="submit"
            class="send-button"
            disabled={@chat.busy or not @model_access.available?}
          >
            <span :if={!@chat.busy}>Send</span>
            <span :if={@chat.busy}>Working…</span>
          </button>
        </.form>
      </section>
    </main>
    """
  end

  defp connect_codex(socket, chat) do
    adapter = Application.get_env(:bnest_app, :codex_session, BnestApp.Codex.PortSession)

    case adapter.open(self(), chat.thread_id, chat.model, chat.reasoning_effort) do
      {:ok, session} ->
        socket = assign(socket, session_adapter: adapter, codex_session: session)
        recover_pending_turn(socket)

      {:error, _reason} when not is_nil(chat.thread_id) ->
        fresh = %{
          chat
          | thread_id: nil,
            error:
              "The previous Codex conversation was unavailable. Your transcript is preserved in a fresh conversation."
        }

        case adapter.open(self(), nil, fresh.model, fresh.reasoning_effort) do
          {:ok, session} ->
            socket = assign(socket, chat: fresh, session_adapter: adapter, codex_session: session)
            {:ok, persist_chat(socket)}

          {:error, _reason} ->
            {:ok, assign(socket, chat: Chat.fail(fresh, "Codex is not available."))}
        end

      {:error, _reason} ->
        {:ok, assign(socket, chat: Chat.fail(chat, "Codex is not available."))}
    end
  end

  defp restore_chat(socket, default_model, models) do
    owner_id = socket.assigns.current_user["userId"]

    case DataRepository.read(:chat, owner_id) do
      {:ok, record} ->
        case Chat.restore(record["state"]) do
          {:ok, restored} -> {normalize_model(restored, default_model, models), record}
          :error -> {new_chat(default_model), nil}
        end

      {:error, _missing_or_invalid} ->
        chat =
          if legacy_browser_user?(socket),
            do: restore_browser_chat(socket, default_model),
            else: new_chat(default_model)

        {normalize_model(chat, default_model, models), nil}
    end
  end

  defp restore_browser_chat(socket, default_model) do
    if connected?(socket) do
      decode_browser_chat(get_connect_params(socket), default_model)
    else
      new_chat(default_model)
    end
  end

  defp decode_browser_chat(%{"chat" => encoded}, default_model) when is_binary(encoded) do
    with true <- byte_size(encoded) <= @max_snapshot_bytes,
         {:ok, snapshot} <- Jason.decode(encoded),
         {:ok, restored} <- Chat.restore(snapshot) do
      restored
    else
      _invalid_or_missing -> new_chat(default_model)
    end
  end

  defp decode_browser_chat(_params, default_model), do: new_chat(default_model)

  defp persist_chat(socket) do
    case Chat.snapshot(socket.assigns.chat) do
      {:ok, snapshot} -> persist_chat_snapshot(socket, snapshot)
      :error -> socket
    end
  end

  defp recover_pending_turn(socket) do
    case Chat.continuation_prompt(socket.assigns.chat) do
      {:ok, prompt, chat} ->
        socket = socket |> assign(:chat, chat) |> persist_chat()

        case socket.assigns.session_adapter.send_prompt(socket.assigns.codex_session, prompt) do
          :ok ->
            {:ok, socket}

          {:error, _reason} ->
            {:ok,
             socket
             |> assign(:chat, Chat.fail(chat, "Codex is not available."))
             |> persist_chat()}
        end

      {:error, :none} ->
        {:ok, socket}

      {:error, :already_attempted} ->
        chat =
          Chat.fail(
            socket.assigns.chat,
            "The previous response was interrupted. Your transcript is preserved; send a new message to continue."
          )

        {:ok, socket |> assign(:chat, chat) |> persist_chat()}
    end
  end

  defp schedule_checkpoint(%{assigns: %{checkpoint_timer: nil}} = socket) do
    timer = Process.send_after(self(), :checkpoint_chat, 1_000)
    assign(socket, :checkpoint_timer, timer)
  end

  defp schedule_checkpoint(socket), do: socket

  defp persist_chat_snapshot(
         %{assigns: %{central_record: nil, current_user: %{"migrationMode" => true}}} = socket,
         snapshot
       ),
       do: push_event(socket, "persist-chat", snapshot)

  defp persist_chat_snapshot(socket, snapshot) do
    owner_id = socket.assigns.current_user["userId"]
    previous = socket.assigns.central_record

    candidate = %{
      "schemaVersion" => 1,
      "recordType" => "chat",
      "ownerId" => owner_id,
      "sourceImportId" => if(previous, do: previous["sourceImportId"], else: nil),
      "state" => snapshot,
      "updatedAt" => timestamp()
    }

    expected_revision = if previous, do: previous["revision"], else: nil

    case DataRepository.write(:chat, owner_id, expected_revision, candidate) do
      {:ok, record} ->
        assign(socket, :central_record, record)

      {:error, :stale} ->
        assign(
          socket,
          :chat,
          Chat.fail(socket.assigns.chat, "Newer chat data exists. Reload before continuing.")
        )

      {:error, _reason} ->
        assign(
          socket,
          :chat,
          Chat.fail(
            socket.assigns.chat,
            "Chat could not be saved. Your previous saved chat is unchanged."
          )
        )
    end
  end

  defp clear_chat_persistence(
         %{assigns: %{central_record: nil, current_user: %{"migrationMode" => true}}} = socket
       ),
       do: push_event(socket, "clear-chat-storage", %{})

  defp clear_chat_persistence(socket), do: persist_chat(socket)

  defp legacy_browser_user?(socket),
    do: socket.assigns.current_user["migrationMode"] == true

  defp replace_codex(socket, chat) do
    socket.assigns.session_adapter.close(socket.assigns.codex_session)

    socket = assign(socket, :chat, chat)
    {:ok, socket} = connect_codex(socket, chat)
    persist_chat(socket)
  end

  defp prompt_form(prompt \\ ""), do: to_form(%{"prompt" => prompt}, as: :chat)

  defp new_chat(model), do: Chat.new(model.id, ModelCatalog.reasoning_effort(model))

  defp normalize_model(chat, default_model, models) do
    selected_model =
      selected_model(models, chat.model) || default_model

    reasoning_effort = ModelCatalog.reasoning_effort(selected_model, chat.reasoning_effort)
    {:ok, chat} = Chat.select_model(chat, selected_model.id, reasoning_effort)

    chat
  end

  defp model_display_name(models, model_id) do
    selected_model(models, model_id).display_name
  end

  defp selected_model(models, model_id), do: Enum.find(models, &(&1.id == model_id))

  defp model_selection_allowed?(socket),
    do: Map.get(socket.assigns, :model_access, %{selectable?: true}).selectable?

  defp assistant_content(%{content: "", streaming: true}), do: "Thinking…"
  defp assistant_content(message), do: message.content

  defp message_class(%{role: :visitor}), do: "message message-visitor"
  defp message_class(%{role: :assistant}), do: "message message-assistant"

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
