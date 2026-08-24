defmodule BnestAppWeb.ChatLive do
  use BnestAppWeb, :live_view

  alias BnestApp.Chat
  alias BnestApp.Codex.Settings

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:chat, Chat.new())
      |> assign(:form, prompt_form())
      |> assign(:session_adapter, nil)
      |> assign(:codex_session, nil)

    if connected?(socket), do: connect_codex(socket), else: {:ok, socket}
  end

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

  @impl Phoenix.LiveView
  def handle_info({:codex, {:assistant_update, text}}, socket) do
    {:noreply, update(socket, :chat, &Chat.update_assistant(&1, text))}
  end

  def handle_info({:codex, :turn_completed}, socket) do
    {:noreply, update(socket, :chat, &Chat.complete/1)}
  end

  def handle_info({:codex, {:error, message}}, socket) do
    {:noreply, update(socket, :chat, &Chat.fail(&1, message))}
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
          <div>
            <p class="chat-kicker">Local Codex chat</p>
            <h1 id="chat-title">Beaver Nest</h1>
          </div>
          <span
            class="model-badge"
            data-model={Settings.model()}
            data-reasoning-effort={Settings.reasoning_effort()}
          >
            {Settings.label()}
          </span>
        </header>

        <div class="conversation" aria-live="polite" aria-label="Conversation">
          <div :if={@chat.messages == []} class="empty-state">
            <p>Ask Codex about this repository.</p>
            <span>This conversation disappears when you refresh.</span>
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

  defp connect_codex(socket) do
    adapter = Application.get_env(:bnest_app, :codex_session, BnestApp.Codex.PortSession)
    {:ok, session} = adapter.open(self())
    {:ok, assign(socket, session_adapter: adapter, codex_session: session)}
  end

  defp prompt_form, do: to_form(%{"prompt" => ""}, as: :chat)

  defp assistant_content(%{content: "", streaming: true}), do: "Thinking…"
  defp assistant_content(message), do: message.content

  defp message_class(%{role: :visitor}), do: "message message-visitor"
  defp message_class(%{role: :assistant}), do: "message message-assistant"
end
