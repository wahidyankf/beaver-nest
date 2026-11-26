defmodule BnestAppWeb.ChatLive do
  use BnestAppWeb, :live_view

  alias BnestApp.CodexChat

  alias BnestApp.CodexChat.Domain.{
    Conversations,
    ModelAccess,
    RepositoryAccess,
    Settings,
    Transcript
  }

  alias BnestAppWeb.ChatComponents

  @max_snapshot_bytes 500_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    model_access = CodexChat.model_access(socket.assigns.current_user)
    {conversations, central_record} = restore_conversations(socket, model_access)

    {:ok, %{transcript: chat}} = CodexChat.selected_conversation(conversations)

    chat =
      if model_access.available?, do: chat, else: Transcript.fail(chat, model_access.error)

    socket =
      socket
      |> assign(:chat, chat)
      |> assign(:conversations, conversations)
      |> assign(:models, model_access.models)
      |> assign(:model_access, model_access)
      |> assign(
        :repository_write_allowed?,
        RepositoryAccess.can_enable_write?(socket.assigns.current_user)
      )
      |> assign(:repository_write_enabled?, false)
      |> assign(:repository_access_mode, :read_only)
      |> assign(:form, prompt_form())
      |> assign(:renaming_id, nil)
      |> assign(:central_record, central_record)
      |> assign(:codex_session, nil)
      |> assign(:checkpoint_timer, nil)

    if connected?(socket) and model_access.available?,
      do: connect_codex(socket, chat),
      else: {:ok, socket}
  end

  # The rail links patch the selected conversation into the address, so a reload or a
  # shared address opens that conversation. Selecting the same or an unknown id is a
  # no-op: the page keeps its session.
  @impl Phoenix.LiveView
  def handle_params(%{"conversation" => id}, _uri, socket) when is_binary(id) do
    if id == socket.assigns.conversations.selected_id do
      {:noreply, socket}
    else
      socket = sync_transcript(socket)

      case CodexChat.select_conversation(socket.assigns.conversations, id) do
        {:ok, conversations} -> {:noreply, reconnect_conversation(socket, conversations)}
        {:error, _unknown} -> {:noreply, socket}
      end
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # The role's rules decide what a switch may change, so a forged model or effort is refused here too.
  def handle_event("select_model", %{"model" => model_id}, socket) do
    with false <- socket.assigns.chat.busy,
         {:ok, model, reasoning_effort} <-
           ModelAccess.select_model(
             Map.get(socket.assigns, :model_access),
             model_id,
             socket.assigns.chat.reasoning_effort
           ),
         {:ok, chat} <- Transcript.select_model(socket.assigns.chat, model.id, reasoning_effort) do
      {:noreply, replace_codex(socket, chat)}
    else
      _busy_or_refused -> {:noreply, socket}
    end
  end

  def handle_event("ignore_model_recovery", _params, socket), do: {:noreply, socket}

  def handle_event("select_effort", %{"reasoning_effort" => reasoning_effort}, socket) do
    models = Map.get(socket.assigns, :models, CodexChat.models())

    with false <- socket.assigns.chat.busy,
         %{} = model <- selected_model(models, socket.assigns.chat.model),
         {:ok, effort} <-
           ModelAccess.select_effort(
             Map.get(socket.assigns, :model_access),
             model,
             reasoning_effort
           ),
         {:ok, chat} <- Transcript.select_model(socket.assigns.chat, model.id, effort) do
      {:noreply, replace_codex(socket, chat)}
    else
      _busy_or_refused -> {:noreply, socket}
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

  # On reconnect an empty composer sends no prompt, only its target. There is no draft to recover.
  def handle_event("recover_draft", _params, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("send", _params, %{assigns: %{model_access: %{available?: false}}} = socket),
    do: {:noreply, socket}

  def handle_event("send", %{"chat" => %{"prompt" => prompt}}, socket) do
    case Transcript.submit(socket.assigns.chat, prompt) do
      {:ok, chat} ->
        socket =
          socket
          |> assign(:chat, chat)
          |> assign(:form, prompt_form())
          |> maybe_name_conversation(prompt)
          |> persist_chat()

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

  # A second tab: the live chat is stored back first, so switching never loses a
  # streamed reply, then the selected conversation is connected and saved.
  def handle_event("new_conversation", _params, socket) do
    socket = sync_transcript(socket)

    case CodexChat.create_conversation(socket.assigns.conversations) do
      {:ok, _id, conversations} -> {:noreply, reconnect_conversation(socket, conversations)}
      {:error, _limit} -> {:noreply, socket}
    end
  end

  def handle_event("select_conversation", %{"id" => id}, socket) do
    if id != socket.assigns.conversations.selected_id do
      socket = sync_transcript(socket)

      case CodexChat.select_conversation(socket.assigns.conversations, id) do
        {:ok, conversations} -> {:noreply, reconnect_conversation(socket, conversations)}
        {:error, _unknown} -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_conversation", _params, socket), do: {:noreply, socket}

  # Deleting the selected conversation closes its session first, then connects the
  # conversation that takes its place. Deleting another one keeps the session.
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    {:noreply, drop_conversation(sync_transcript(socket), id)}
  end

  def handle_event("delete_conversation", _params, socket), do: {:noreply, socket}

  def handle_event("rename_conversation", %{"conversation_id" => id, "title" => title}, socket) do
    case CodexChat.rename_conversation(socket.assigns.conversations, id, title || "") do
      {:ok, conversations} ->
        socket = socket |> assign(:conversations, conversations) |> assign(:renaming_id, nil)
        {:noreply, persist_chat(socket)}

      {:error, _refused} ->
        {:noreply, socket}
    end
  end

  def handle_event("rename_conversation", _params, socket), do: {:noreply, socket}

  # The rename form opens only on its edit icon, so the rail keeps one compact
  # row per conversation. Toggling the open icon closes it again.
  def handle_event("toggle_rename", %{"id" => id}, socket) do
    current = Map.get(socket.assigns, :renaming_id)
    {:noreply, assign(socket, :renaming_id, if(current == id, do: nil, else: id))}
  end

  def handle_event("toggle_rename", _params, socket), do: {:noreply, socket}

  defp drop_conversation(socket, id) do
    selected_before = socket.assigns.conversations.selected_id

    case CodexChat.delete_conversation(socket.assigns.conversations, id) do
      {:ok, conversations} when id == selected_before ->
        reconnect_conversation(socket, conversations)

      {:ok, conversations} ->
        persist_chat(assign(socket, :conversations, conversations))

      {:error, _unknown} ->
        socket
    end
  end

  defp clear_available_chat(socket) do
    close_codex(socket.assigns.codex_session)

    {:ok, %{id: id}} = CodexChat.selected_conversation(socket.assigns.conversations)
    fresh = Transcript.new(socket.assigns.chat.model, socket.assigns.chat.reasoning_effort)

    {:ok, conversations} =
      CodexChat.put_conversation_transcript(socket.assigns.conversations, id, fresh)

    {:ok, renamed} =
      CodexChat.rename_conversation(conversations, id, CodexChat.default_conversation_title(""))

    socket =
      socket
      |> assign(
        repository_write_enabled?: false,
        repository_access_mode: :read_only,
        codex_session: nil
      )
      |> assign(:conversations, renamed)
      |> assign(:chat, fresh)
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
      <aside class="conversation-rail" data-role="conversation-rail" aria-label="Chats">
        <button type="button" data-role="new-conversation" phx-click="new_conversation">
          New chat
        </button>
        <ul>
          <li
            :for={entry <- CodexChat.list_conversations(@conversations)}
            data-role="conversation-item"
            data-conversation-id={entry.id}
            aria-current={entry.id == @conversations.selected_id && "true"}
          >
            <a
              href={"/chat?conversation=#{entry.id}"}
              data-phx-link="patch"
              data-phx-link-state="push"
              data-role="select-conversation"
              data-conversation-id={entry.id}
            >
              {entry.title}
            </a>
            <span
              data-role="conversation-updated"
              title={DateTime.to_iso8601(entry.updated_at)}
            >
              {format_conversation_updated(entry.updated_at)}
            </span>
            <div class="conversation-actions">
              <button
                type="button"
                data-role="rename-toggle"
                data-conversation-id={entry.id}
                phx-click="toggle_rename"
                phx-value-id={entry.id}
                aria-expanded={to_string(@renaming_id == entry.id)}
                aria-controls={"rename-form-#{entry.id}"}
                aria-label="Rename conversation"
                title="Rename conversation"
              >
                <svg
                  aria-hidden="true"
                  width="16"
                  height="16"
                  viewBox="0 0 16 16"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M11.5 2.5a1.8 1.8 0 0 1 2.5 2.5L5 14l-3.2.8.8-3.2 8.9-9.1Z" />
                </svg>
              </button>
              <button
                type="button"
                data-role="delete-conversation"
                phx-click="delete_conversation"
                phx-value-id={entry.id}
                aria-label="Delete conversation"
                title="Delete conversation"
              >
                <svg
                  aria-hidden="true"
                  width="16"
                  height="16"
                  viewBox="0 0 16 16"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M2.5 4h11M6.5 4V2.8a.3.3 0 0 1 .3-.3h2.4a.3.3 0 0 1 .3.3V4M4 4l.7 9.2a.6.6 0 0 0 .6.6h5.4a.6.6 0 0 0 .6-.6L12 4" />
                  <path d="M6.7 7v4M9.3 7v4" />
                </svg>
              </button>
            </div>
            <form
              :if={@renaming_id == entry.id}
              id={"rename-form-#{entry.id}"}
              phx-submit="rename_conversation"
              class="conversation-rename"
            >
              <input type="hidden" name="conversation_id" value={entry.id} />
              <input
                type="text"
                name="title"
                value={entry.title}
                data-role="rename-input"
                aria-label="Conversation title"
              />
              <div class="conversation-rename-actions">
                <button type="submit" data-role="rename-submit">Save</button>
                <button
                  type="button"
                  data-role="rename-cancel"
                  phx-click="toggle_rename"
                  phx-value-id={entry.id}
                >
                  Cancel
                </button>
              </div>
            </form>
          </li>
        </ul>
      </aside>
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
          <div class="chat-controls">
            <%!-- The Options button comes first in source order, so keyboard focus follows the phone layout. --%>
            <button
              type="button"
              class="chat-options-toggle"
              data-role="chat-options-toggle"
              aria-expanded="false"
              aria-controls="chat-options"
            >
              Options
            </button>
            <%!-- The access state and its toggle sit outside the scrolling row, so they are on screen at every width. --%>
            <span
              class="chat-access"
              data-role="repository-access"
              data-mode={repository_mode_value(@repository_access_mode)}
              aria-live="polite"
            >
              <button
                :if={@repository_write_allowed?}
                type="button"
                class={[
                  "repository-access-badge",
                  "repository-write-toggle",
                  @repository_write_enabled? && "repository-access-badge-write"
                ]}
                data-role="repository-write-toggle"
                phx-click="set_repository_write"
                phx-value-enabled={to_string(not @repository_write_enabled?)}
                aria-label={repository_write_toggle_label(@repository_write_enabled?)}
                disabled={@chat.busy}
              >
                {repository_access_text(@repository_write_enabled?)}
              </button>
              <span
                :if={not @repository_write_allowed?}
                class={[
                  "repository-access-badge",
                  @repository_write_enabled? && "repository-access-badge-write"
                ]}
              >
                {repository_access_text(@repository_write_enabled?)}
              </span>
            </span>
            <%!-- The model badge stays outside the options panel: a phone shows it without opening Options (ADR 005). --%>
            <span
              class="model-badge"
              data-model={@chat.model}
              data-reasoning-effort={@chat.reasoning_effort}
            >
              {Settings.label(model_display_name(@models, @chat.model), @chat.reasoning_effort)}
            </span>
            <div id="chat-options" class="chat-actions" data-role="chat-options">
              <form
                :if={@model_access.model_selectable?}
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
                :if={@model_access.effort_selectable?}
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
              <%!-- The first click only opens this confirmation (chat_controls.js). Only "Yes, delete" sends the clear. --%>
              <%!-- ignore: LiveView keeps this group's buttons (and the focus on Clear chat) through the clear patch. --%>
              <div
                id="clear-chat-group"
                class="clear-chat"
                data-role="clear-chat-group"
                phx-update="ignore"
              >
                <button
                  type="button"
                  class="clear-chat-button"
                  data-role="clear-chat"
                  aria-expanded="false"
                  aria-controls="clear-chat-confirm"
                >
                  Clear chat
                </button>
                <div
                  id="clear-chat-confirm"
                  class="clear-chat-confirm"
                  role="alertdialog"
                  aria-label="Confirm clearing the chat"
                  aria-describedby="clear-chat-question"
                  data-role="clear-chat-confirm"
                  hidden
                >
                  <p id="clear-chat-question" class="clear-chat-question">Delete all messages?</p>
                  <div class="clear-chat-actions">
                    <button type="button" class="clear-chat-cancel" data-role="clear-chat-cancel">
                      Cancel
                    </button>
                    <button
                      type="button"
                      class="clear-chat-yes"
                      data-role="clear-chat-yes"
                      phx-click="clear"
                    >
                      Yes, delete
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </header>

        <%!-- The hook draws the marked diagrams of every reply (ADR 004, Decision 3). One watcher serves the whole
             conversation, so a reply that changes needs no hook update. --%>
        <div
          id="chat-conversation"
          class="conversation"
          aria-live="polite"
          aria-label="Conversation"
          phx-hook="ChatDiagrams"
        >
          <div :if={@chat.messages == []} class="empty-state">
            <p>Ask Codex about this repository.</p>
            <span>This conversation is saved to your account until you clear it.</span>
          </div>

          <article
            :for={message <- @chat.messages}
            id={
              if message.role == :visitor, do: "message-#{@conversations.selected_id}-#{message.id}"
            }
            class={message_class(message)}
            phx-update={if message.role == :visitor, do: "ignore"}
            data-role="message"
          >
            <p class="message-label">{if message.role == :visitor, do: "You", else: "Codex"}</p>
            <%!-- The text between the tags is the message itself: the formatter must not split it, because
                 the pre-wrap element would show any whitespace the template adds around it. --%>
            <%!-- A visitor's message is Markdown like a reply (the same component and sanitizer). Its raw text is a
                 second element; chat_controls.js switches between them on the client, so the article is ignored by
                 LiveView patches and keeps the view the visitor chose. --%>
            <ChatComponents.own_message
              :if={message.role == :visitor}
              id={message.id}
              content={message.content}
            />
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
            <%!-- A finished reply never changes again, so later patches ignore it: a drawn diagram and an opened
                 source stay as they are. The patch that ends streaming is not ignored, so the diagram marker
                 arrives with it. (ADR 004, Decision 3.) --%>
            <div
              :if={message.role == :assistant and placeholder?(message)}
              id={"assistant-message-#{@conversations.selected_id}-#{message.id}"}
              class="message-content markdown-body"
              data-role="assistant-message"
              data-streaming={to_string(message.streaming)}
              data-update-count={message.update_count}
              phx-no-format
            >Thinking…</div>
            <ChatComponents.markdown_body
              :if={message.role == :assistant and not placeholder?(message)}
              id={"assistant-message-#{@conversations.selected_id}-#{message.id}"}
              phx-update={if message.streaming, do: nil, else: "ignore"}
              content={message.content}
              streaming={message.streaming}
              codex_images={true}
              data-role="assistant-message"
              data-streaming={to_string(message.streaming)}
              data-update-count={message.update_count}
            />
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
            rows="1"
            data-role="chat-composer"
            phx-hook="ChatComposer"
            aria-describedby="chat-composer-hint"
            disabled={not @model_access.available?}
            readonly={@chat.busy}
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
          <p id="chat-composer-hint" class="composer-hint" data-role="composer-hint">
            <span class="hint-keyboard">Enter to send, Shift+Enter for a new line</span>
            <span class="hint-touch">Shift+Enter to send</span>
          </p>
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

  # Stores the live chat back into its conversation, so a switch never loses a
  # reply the page has not saved yet.
  defp sync_transcript(socket) do
    case CodexChat.put_conversation_transcript(
           socket.assigns.conversations,
           socket.assigns.conversations.selected_id,
           socket.assigns.chat
         ) do
      {:ok, conversations} -> assign(socket, :conversations, conversations)
      {:error, _unknown} -> socket
    end
  end

  # Closes the current Codex session, connects the selected conversation and saves
  # the switch, moving the address to the selected conversation. Without an
  # available model there is no session to connect; the tabs still switch.
  defp reconnect_conversation(socket, conversations) do
    close_codex(socket.assigns.codex_session)
    conversations = settle_conversation(conversations, socket.assigns.model_access)
    {:ok, %{id: id, transcript: chat}} = CodexChat.selected_conversation(conversations)

    socket =
      assign(socket,
        conversations: conversations,
        chat: chat,
        codex_session: nil,
        form: prompt_form()
      )

    {:ok, socket} =
      if socket.assigns.model_access.available? do
        connect_codex(socket, chat)
      else
        {:ok, socket}
      end

    socket
    |> persist_chat()
    |> push_patch(to: "/chat?conversation=#{id}")
  end

  defp close_codex(nil), do: :ok
  defp close_codex(session), do: CodexChat.close(session)

  # A conversation without a user-chosen title takes it from its first message.
  defp maybe_name_conversation(socket, prompt) do
    {:ok, %{id: id, title: title}} =
      CodexChat.selected_conversation(socket.assigns.conversations)

    if title == CodexChat.default_conversation_title("") do
      case CodexChat.rename_conversation(
             socket.assigns.conversations,
             id,
             CodexChat.default_conversation_title(prompt)
           ) do
        {:ok, conversations} -> assign(socket, :conversations, conversations)
        {:error, _refused} -> socket
      end
    else
      socket
    end
  end

  defp restore_conversations(socket, access) do
    owner_id = socket.assigns.current_user["userId"]

    case CodexChat.load_conversations(owner_id) do
      {:ok, conversations, record} ->
        {settle_conversation(conversations, access), record}

      {:error, :unrestorable} ->
        {fresh_conversations(access), nil}

      {:error, _missing_or_invalid} ->
        conversations =
          if legacy_browser_user?(socket),
            do: restore_browser_conversations(socket, access),
            else: fresh_conversations(access)

        {settle_conversation(conversations, access), nil}
    end
  end

  defp restore_browser_conversations(socket, access) do
    if connected?(socket) do
      decode_browser_conversations(get_connect_params(socket), access)
    else
      fresh_conversations(access)
    end
  end

  defp decode_browser_conversations(%{"chat" => encoded}, access) when is_binary(encoded) do
    with true <- byte_size(encoded) <= @max_snapshot_bytes,
         {:ok, snapshot} <- Jason.decode(encoded),
         {:ok, conversations} <- Conversations.restore(snapshot, DateTime.utc_now()) do
      conversations
    else
      _invalid_or_missing -> fresh_conversations(access)
    end
  end

  defp decode_browser_conversations(_params, access), do: fresh_conversations(access)

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
    case Conversations.snapshot(synced_conversations(socket)) do
      {:ok, snapshot} -> push_event(socket, "persist-chat", snapshot)
      :error -> socket
    end
  end

  defp persist_chat(socket) do
    owner_id = socket.assigns.current_user["userId"]
    synced = synced_conversations(socket)

    case CodexChat.save_conversations(owner_id, synced, socket.assigns.central_record) do
      {:ok, record} ->
        {:ok, %{transcript: chat}} = CodexChat.selected_conversation(synced)
        assign(socket, conversations: synced, chat: chat, central_record: record)

      {:error, failed} ->
        {:ok, %{transcript: chat}} = CodexChat.selected_conversation(failed)
        assign(socket, conversations: failed, chat: chat)

      :error ->
        socket
    end
  end

  defp synced_conversations(socket) do
    case CodexChat.put_conversation_transcript(
           socket.assigns.conversations,
           socket.assigns.conversations.selected_id,
           socket.assigns.chat
         ) do
      {:ok, conversations} -> conversations
      {:error, _unknown} -> socket.assigns.conversations
    end
  end

  defp clear_chat_persistence(
         %{assigns: %{central_record: nil, current_user: %{"migrationMode" => true}}} = socket
       ) do
    case Conversations.snapshot(synced_conversations(socket)) do
      {:ok, snapshot} -> push_event(socket, "persist-chat", snapshot)
      :error -> push_event(socket, "clear-chat-storage", %{})
    end
  end

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

  defp fresh_conversations(access) do
    {model, reasoning_effort} =
      ModelAccess.settle(
        access,
        Settings.preferred_model(),
        Settings.preferred_reasoning_effort()
      )

    Conversations.new(
      transcript: Transcript.enforce_model(Transcript.new(), model.id, reasoning_effort),
      now: DateTime.utc_now()
    )
  end

  # A saved model or effort the role may no longer use resolves to the role's own choice (ADR 006).
  defp settle_conversation(conversations, access) do
    {:ok, %{id: id, transcript: chat}} = CodexChat.selected_conversation(conversations)
    {model, reasoning_effort} = ModelAccess.settle(access, chat.model, chat.reasoning_effort)

    if chat.model == model.id and chat.reasoning_effort == reasoning_effort do
      conversations
    else
      {:ok, settled} =
        CodexChat.put_conversation_transcript(
          conversations,
          id,
          Transcript.enforce_model(chat, model.id, reasoning_effort)
        )

      settled
    end
  end

  defp format_conversation_updated(updated_at) do
    Calendar.strftime(updated_at, "%Y-%m-%d %H:%M")
  end

  defp model_display_name(models, model_id) do
    selected_model(models, model_id).display_name
  end

  defp selected_model(models, model_id), do: Enum.find(models, &(&1.id == model_id))

  # A reply that has no text yet shows the placeholder, as plain text and never as Markdown.
  defp placeholder?(%{content: "", streaming: true}), do: true
  defp placeholder?(_message), do: false

  defp progress_data_role(:reasoning), do: "codex-reasoning-summary"
  defp progress_data_role(_kind), do: "codex-progress-item"

  defp repository_access_text(true), do: "Repo write enabled"
  defp repository_access_text(false), do: "Repo read-only"

  # The toggle's name carries its state and its action, so a screen reader hears both.
  defp repository_write_toggle_label(true), do: "Repo write enabled. Disable repo writes"
  defp repository_write_toggle_label(false), do: "Repo read-only. Enable repo writes"

  defp progress_label(:reasoning), do: "Reasoning"
  defp progress_label(:activity), do: "Working"
  defp progress_label(:status), do: "Progress"

  defp repository_mode_value(:workspace_write), do: "workspace-write"
  defp repository_mode_value(_mode), do: "read-only"

  defp message_class(%{role: :visitor}), do: "message message-visitor"
  defp message_class(%{role: :assistant}), do: "message message-assistant"
end
