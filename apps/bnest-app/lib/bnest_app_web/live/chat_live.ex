defmodule BnestAppWeb.ChatLive do
  use BnestAppWeb, :live_view

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.{RepositoryAccess, Settings, Transcript}

  @max_snapshot_bytes 500_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    model_access = CodexChat.model_access(socket.assigns.current_user)
    {chat, central_record} = restore_chat(socket, model_access.model, model_access.models)

    chat =
      if model_access.selectable? do
        chat
      else
        Transcript.enforce_model(chat, model_access.model.id, model_access.reasoning_effort)
      end

    chat =
      if model_access.available?, do: chat, else: Transcript.fail(chat, model_access.error)

    socket =
      socket
      |> assign(:chat, chat)
      |> assign(:models, model_access.models)
      |> assign(:model_access, model_access)
      |> assign(
        :repository_write_allowed?,
        RepositoryAccess.can_enable_write?(socket.assigns.current_user)
      )
      |> assign(:repository_write_enabled?, false)
      |> assign(:repository_access_mode, :read_only)
      |> assign(:form, prompt_form())
      |> assign(:central_record, central_record)
      |> assign(:codex_session, nil)
      |> assign(:checkpoint_timer, nil)

    if connected?(socket) and model_access.available?,
      do: connect_codex(socket, chat),
      else: {:ok, socket}
  end

  def handle_event("select_model", %{"model" => model_id}, socket) do
    models = Map.get(socket.assigns, :models, CodexChat.models())

    with true <- model_selection_allowed?(socket),
         false <- socket.assigns.chat.busy,
         %{} = model <- selected_model(models, model_id),
         reasoning_effort =
           CodexChat.reasoning_effort(model, socket.assigns.chat.reasoning_effort),
         {:ok, chat} <- Transcript.select_model(socket.assigns.chat, model.id, reasoning_effort) do
      {:noreply, replace_codex(socket, chat)}
    else
      _busy_or_unknown -> {:noreply, socket}
    end
  end

  def handle_event("ignore_model_recovery", _params, socket), do: {:noreply, socket}

  def handle_event("select_effort", %{"reasoning_effort" => reasoning_effort}, socket) do
    models = Map.get(socket.assigns, :models, CodexChat.models())

    with true <- model_selection_allowed?(socket),
         false <- socket.assigns.chat.busy,
         %{} = model <- selected_model(models, socket.assigns.chat.model),
         true <- reasoning_effort in model.supported_reasoning_efforts,
         {:ok, chat} <-
           Transcript.select_model(
             socket.assigns.chat,
             socket.assigns.chat.model,
             reasoning_effort
           ) do
      {:noreply, replace_codex(socket, chat)}
    else
      _busy_or_unsupported -> {:noreply, socket}
    end
  end

  def handle_event("ignore_effort_recovery", _params, socket), do: {:noreply, socket}

  def handle_event(
        "set_repository_write",
        %{"enabled" => enabled},
        %{assigns: %{chat: %{busy: false}}} = socket
      )
      when enabled in ["true", "false"] do
    requested? = enabled == "true"

    if not requested? or socket.assigns.repository_write_allowed? do
      {:noreply, switch_repository_access(socket, requested?)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_repository_write", _params, socket), do: {:noreply, socket}

  def handle_event("recover_draft", %{"chat" => %{"prompt" => prompt}}, socket) do
    {:noreply, assign(socket, :form, prompt_form(prompt))}
  end

  @impl Phoenix.LiveView
  def handle_event("send", _params, %{assigns: %{model_access: %{available?: false}}} = socket),
    do: {:noreply, socket}

  def handle_event("send", %{"chat" => %{"prompt" => prompt}}, socket) do
    case Transcript.submit(socket.assigns.chat, prompt) do
      {:ok, chat} ->
        socket = socket |> assign(:chat, chat) |> assign(:form, prompt_form()) |> persist_chat()

        case CodexChat.send_prompt(socket.assigns.codex_session, chat, prompt) do
          {:ok, _chat} -> {:noreply, socket}
          {:error, failed} -> {:noreply, socket |> assign(:chat, failed) |> persist_chat()}
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
    CodexChat.close(socket.assigns.codex_session)

    socket =
      socket
      |> assign(
        repository_write_enabled?: false,
        repository_access_mode: :read_only,
        codex_session: nil
      )
      |> assign(
        :chat,
        Transcript.new(socket.assigns.chat.model, socket.assigns.chat.reasoning_effort)
      )
      |> assign(:form, prompt_form())
      |> clear_chat_persistence()

    {:ok, socket} = connect_codex(socket, socket.assigns.chat)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:codex, session, {:resume_failed, _message}},
        %{assigns: %{codex_session: session}} = socket
      ) do
    case CodexChat.replace_conversation(
           session,
           socket.assigns.chat,
           socket.assigns.repository_access_mode
         ) do
      {:ok, replacement, fresh} ->
        socket = assign(socket, chat: fresh, codex_session: replacement)
        {:noreply, persist_chat(socket)}

      {:error, failed} ->
        {:noreply, socket |> assign(:chat, failed) |> persist_chat()}
    end
  end

  def handle_info({:codex, session, event}, %{assigns: %{codex_session: session}} = socket) do
    case CodexChat.apply_event(socket.assigns.chat, event) do
      {:persist, chat} -> {:noreply, socket |> assign(:chat, chat) |> persist_chat()}
      {:checkpoint, chat} -> {:noreply, socket |> assign(:chat, chat) |> schedule_checkpoint()}
      :ignore -> {:noreply, socket}
    end
  end

  def handle_info({:codex, _stale_session, _event}, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_info(:checkpoint_chat, socket) do
    {:noreply, socket |> assign(:checkpoint_timer, nil) |> persist_chat()}
  end

  @impl Phoenix.LiveView
  def terminate(_reason, %{assigns: %{codex_session: nil}}), do: :ok

  def terminate(_reason, socket), do: CodexChat.close(socket.assigns.codex_session)

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
            <span
              class={[
                "repository-access-badge",
                @repository_write_enabled? && "repository-access-badge-write"
              ]}
              data-role="repository-access"
              data-mode={repository_mode_value(@repository_access_mode)}
              aria-live="polite"
            >
              {if @repository_write_enabled?, do: "Repo write enabled", else: "Repo read-only"}
            </span>
            <button
              :if={@repository_write_allowed?}
              type="button"
              class="repository-write-toggle"
              data-role="repository-write-toggle"
              phx-click="set_repository_write"
              phx-value-enabled={to_string(not @repository_write_enabled?)}
              aria-pressed={to_string(@repository_write_enabled?)}
              disabled={@chat.busy}
            >
              {if @repository_write_enabled?,
                do: "Disable repo writes",
                else: "Enable repo writes"}
            </button>
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
            <details
              :if={message.role == :assistant and message.progress != []}
              class="codex-progress"
              data-role="codex-thinking"
              open={message.streaming}
            >
              <summary data-role="codex-thinking-summary">Thinking</summary>
              <ol>
                <li
                  :for={progress <- message.progress}
                  data-role={progress_data_role(progress.kind)}
                  data-kind={progress.kind}
                >
                  <span class="codex-progress-label">{progress_label(progress.kind)}</span>
                  <span>{progress.content}</span>
                </li>
              </ol>
            </details>
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
    case CodexChat.open_conversation(chat, socket.assigns.repository_access_mode) do
      {:ok, session, _chat} ->
        socket |> assign(:codex_session, session) |> recover_pending_turn()

      {:fresh, session, fresh} ->
        {:ok, socket |> assign(chat: fresh, codex_session: session) |> persist_chat()}

      {:error, failed} ->
        {:ok, assign(socket, chat: failed)}
    end
  end

  defp restore_chat(socket, default_model, models) do
    owner_id = socket.assigns.current_user["userId"]

    case CodexChat.load_transcript(owner_id) do
      {:ok, restored, record} ->
        {normalize_model(restored, default_model, models), record}

      {:error, :unrestorable} ->
        {new_chat(default_model), nil}

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
         {:ok, restored} <- Transcript.restore(snapshot) do
      restored
    else
      _invalid_or_missing -> new_chat(default_model)
    end
  end

  defp decode_browser_chat(_params, default_model), do: new_chat(default_model)

  defp recover_pending_turn(socket) do
    case CodexChat.recover_pending_turn(socket.assigns.chat) do
      {:resend, prompt, chat} ->
        socket = socket |> assign(:chat, chat) |> persist_chat()

        case CodexChat.send_prompt(socket.assigns.codex_session, chat, prompt) do
          {:ok, _chat} -> {:ok, socket}
          {:error, failed} -> {:ok, socket |> assign(:chat, failed) |> persist_chat()}
        end

      :none ->
        {:ok, socket}

      {:interrupted, chat} ->
        {:ok, socket |> assign(:chat, chat) |> persist_chat()}
    end
  end

  defp schedule_checkpoint(%{assigns: %{checkpoint_timer: nil}} = socket) do
    timer = Process.send_after(self(), :checkpoint_chat, 1_000)
    assign(socket, :checkpoint_timer, timer)
  end

  defp schedule_checkpoint(socket), do: socket

  # Until a legacy browser user's chat is centralized, the browser keeps it.
  defp persist_chat(
         %{assigns: %{central_record: nil, current_user: %{"migrationMode" => true}}} = socket
       ) do
    case Transcript.snapshot(socket.assigns.chat) do
      {:ok, snapshot} -> push_event(socket, "persist-chat", snapshot)
      :error -> socket
    end
  end

  defp persist_chat(socket) do
    owner_id = socket.assigns.current_user["userId"]

    case CodexChat.save_transcript(owner_id, socket.assigns.chat, socket.assigns.central_record) do
      {:ok, record} -> assign(socket, :central_record, record)
      {:error, failed} -> assign(socket, :chat, failed)
      :error -> socket
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
    CodexChat.close(socket.assigns.codex_session)

    socket = assign(socket, :chat, chat)
    {:ok, socket} = connect_codex(socket, chat)
    persist_chat(socket)
  end

  defp switch_repository_access(socket, requested?) do
    CodexChat.close(socket.assigns.codex_session)

    mode = RepositoryAccess.mode(socket.assigns.current_user, requested?)

    socket =
      assign(socket,
        repository_write_enabled?: mode == :workspace_write,
        repository_access_mode: mode,
        codex_session: nil
      )

    {:ok, switched} = connect_codex(socket, socket.assigns.chat)

    if mode == :workspace_write and is_nil(switched.assigns.codex_session) do
      fallback =
        switched
        |> assign(
          repository_write_enabled?: false,
          repository_access_mode: :read_only,
          codex_session: nil
        )
        |> update(
          :chat,
          &Transcript.fail(
            &1,
            "Repository write access could not be enabled. Chat remains read-only."
          )
        )

      {:ok, read_only} = connect_codex(fallback, fallback.assigns.chat)
      read_only
    else
      switched
    end
  end

  defp prompt_form(prompt \\ ""), do: to_form(%{"prompt" => prompt}, as: :chat)

  defp new_chat(model), do: Transcript.new(model.id, CodexChat.reasoning_effort(model))

  defp normalize_model(chat, default_model, models) do
    selected_model =
      selected_model(models, chat.model) || default_model

    reasoning_effort = CodexChat.reasoning_effort(selected_model, chat.reasoning_effort)
    Transcript.enforce_model(chat, selected_model.id, reasoning_effort)
  end

  defp model_display_name(models, model_id) do
    selected_model(models, model_id).display_name
  end

  defp selected_model(models, model_id), do: Enum.find(models, &(&1.id == model_id))

  defp model_selection_allowed?(socket),
    do: Map.get(socket.assigns, :model_access, %{selectable?: true}).selectable?

  defp assistant_content(%{content: "", streaming: true}), do: "Thinking…"
  defp assistant_content(message), do: message.content

  defp progress_data_role(:reasoning), do: "codex-reasoning-summary"
  defp progress_data_role(_kind), do: "codex-progress-item"

  defp progress_label(:reasoning), do: "Reasoning"
  defp progress_label(:activity), do: "Working"
  defp progress_label(:status), do: "Progress"

  defp repository_mode_value(:workspace_write), do: "workspace-write"
  defp repository_mode_value(_mode), do: "read-only"

  defp message_class(%{role: :visitor}), do: "message message-visitor"
  defp message_class(%{role: :assistant}), do: "message message-assistant"
end
