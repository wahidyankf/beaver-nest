defmodule BnestAppWeb.ChatLive do
  use BnestAppWeb, :live_view

  alias BnestApp.Chat
  alias BnestApp.Codex.{ModelCatalog, Settings}

  @max_snapshot_bytes 500_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    models = ModelCatalog.all()
    default_model = ModelCatalog.default()
    chat = restore_chat(socket, default_model)

    socket =
      socket
      |> assign(:chat, chat)
      |> assign(:models, models)
      |> assign(:form, prompt_form())
      |> assign(:session_adapter, nil)
      |> assign(:codex_session, nil)

    if connected?(socket), do: connect_codex(socket, chat), else: {:ok, socket}
  end

  def handle_event("select_model", %{"model" => model_id}, socket) do
    with false <- socket.assigns.chat.busy,
         {:ok, model} <- ModelCatalog.fetch(model_id),
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
    with false <- socket.assigns.chat.busy,
         {:ok, model} <- ModelCatalog.fetch(socket.assigns.chat.model),
         true <- reasoning_effort in model.supported_reasoning_efforts,
         {:ok, chat} <-
           Chat.select_model(socket.assigns.chat, socket.assigns.chat.model, reasoning_effort) do
      {:noreply, replace_codex(socket, chat)}
    else
      _busy_or_unsupported -> {:noreply, socket}
    end
  end

  def handle_event("ignore_effort_recovery", _params, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("send", %{"chat" => %{"prompt" => prompt}}, socket) do
    case Chat.submit(socket.assigns.chat, prompt) do
      {:ok, chat} ->
        chat =
          case socket.assigns.session_adapter.send_prompt(socket.assigns.codex_session, prompt) do
            :ok -> chat
            {:error, _reason} -> Chat.fail(chat, "Codex is not available.")
          end

        {:noreply, socket |> assign(:chat, chat) |> assign(:form, prompt_form())}

      {:error, chat} ->
        {:noreply, assign(socket, :chat, chat)}
    end
  end

  def handle_event("clear", _params, socket) do
    socket.assigns.session_adapter.close(socket.assigns.codex_session)

    socket =
      socket
      |> assign(
        :chat,
        Chat.new(socket.assigns.chat.model, socket.assigns.chat.reasoning_effort)
      )
      |> assign(:form, prompt_form())
      |> push_event("clear-chat-storage", %{})

    {:ok, socket} = connect_codex(socket, socket.assigns.chat)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:codex, session, {:thread_started, thread_id}},
        %{assigns: %{codex_session: session}} = socket
      ) do
    {:noreply, update(socket, :chat, &Chat.put_thread_id(&1, thread_id))}
  end

  def handle_info(
        {:codex, session, {:assistant_update, text}},
        %{assigns: %{codex_session: session}} = socket
      ) do
    {:noreply, update(socket, :chat, &Chat.update_assistant(&1, text))}
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
    {:noreply, update(socket, :chat, &Chat.fail(&1, message))}
  end

  def handle_info({:codex, _stale_session, _event}, socket), do: {:noreply, socket}

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
          <div>
            <p class="chat-kicker">Local Codex chat</p>
            <h1 id="chat-title">Beaver Nest</h1>
          </div>
          <div class="chat-actions">
            <form
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
            <span>This conversation stays in this browser tab until you clear it.</span>
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

        <.form for={@form} phx-submit="send" class="composer">
          <.input
            field={@form[:prompt]}
            type="textarea"
            label="Message"
            placeholder="Ask Codex…"
            rows="3"
            data-role="chat-composer"
            disabled={@chat.busy}
            required
          />
          <button type="submit" class="send-button" disabled={@chat.busy}>
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

    {:ok, session} =
      adapter.open(self(), chat.thread_id, chat.model, chat.reasoning_effort)

    {:ok, assign(socket, session_adapter: adapter, codex_session: session)}
  end

  defp restore_chat(socket, default_model) do
    chat =
      if connected?(socket) do
        with %{"chat" => encoded} when is_binary(encoded) <- get_connect_params(socket),
             true <- byte_size(encoded) <= @max_snapshot_bytes,
             {:ok, snapshot} <- Jason.decode(encoded),
             {:ok, restored} <- Chat.restore(snapshot) do
          restored
        else
          _invalid_or_missing -> new_chat(default_model)
        end
      else
        new_chat(default_model)
      end

    normalize_model(chat, default_model)
  end

  defp persist_chat(socket) do
    case Chat.snapshot(socket.assigns.chat) do
      {:ok, snapshot} -> push_event(socket, "persist-chat", snapshot)
      :error -> socket
    end
  end

  defp replace_codex(socket, chat) do
    socket.assigns.session_adapter.close(socket.assigns.codex_session)

    socket = assign(socket, :chat, chat)
    {:ok, socket} = connect_codex(socket, chat)
    persist_chat(socket)
  end

  defp prompt_form, do: to_form(%{"prompt" => ""}, as: :chat)

  defp new_chat(model), do: Chat.new(model.id, ModelCatalog.reasoning_effort(model))

  defp normalize_model(chat, default_model) do
    selected_model =
      case ModelCatalog.fetch(chat.model) do
        {:ok, model} -> model
        :error -> default_model
      end

    reasoning_effort = ModelCatalog.reasoning_effort(selected_model, chat.reasoning_effort)
    {:ok, chat} = Chat.select_model(chat, selected_model.id, reasoning_effort)

    chat
  end

  defp model_display_name(models, model_id) do
    selected_model(models, model_id).display_name
  end

  defp selected_model(models, model_id), do: Enum.find(models, &(&1.id == model_id))

  defp assistant_content(%{content: "", streaming: true}), do: "Thinking…"
  defp assistant_content(message), do: message.content

  defp message_class(%{role: :visitor}), do: "message message-visitor"
  defp message_class(%{role: :assistant}), do: "message message-assistant"
end
