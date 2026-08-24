defmodule BnestApp.Behaviour.UnitHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver

  alias BnestApp.Chat
  alias Phoenix.HTML.Safe

  @impl true
  def open(context, "/") do
    render_chat(context, Chat.new())
  end

  @impl true
  def heading_visible?(context, heading) do
    context.page
    |> LazyHTML.query("h1")
    |> LazyHTML.text()
    |> Kernel.==(heading)
  end

  @impl true
  def text_visible?(context, text) do
    context.page
    |> LazyHTML.query(".model-badge")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(text)
  end

  @impl true
  def conversation_empty?(context) do
    context.page
    |> LazyHTML.query("[data-role=message]")
    |> Enum.empty?()
  end

  @impl true
  def composer_available?(context) do
    enabled?(context.page, "textarea") and enabled?(context.page, ".send-button")
  end

  @impl true
  def composer_unavailable?(context) do
    not enabled?(context.page, "textarea") and not enabled?(context.page, ".send-button")
  end

  @impl true
  def attempt_empty_message(context) do
    {:error, chat} = Chat.submit(context.chat, "   ")
    render_chat(context, chat)
  end

  @impl true
  def send_message(context, message) do
    {:ok, chat} = Chat.submit(context.chat, message)
    render_chat(context, chat)
  end

  @impl true
  def attempt_message_before_finished(context, message) do
    {:error, chat} = Chat.submit(context.chat, message)
    render_chat(context, chat)
  end

  @impl true
  def visitor_message_visible?(context, message) do
    context.page
    |> LazyHTML.query("[data-role=user-message]")
    |> Enum.any?(fn element -> element |> LazyHTML.text() |> String.trim() == message end)
  end

  @impl true
  def visitor_message_absent?(context, message) do
    not visitor_message_visible?(context, message)
  end

  @impl true
  def stream_codex_response(context) do
    chat =
      context.chat
      |> Chat.update_assistant("Fixture response")
      |> Chat.update_assistant("Fixture response complete.")
      |> Chat.complete()

    context = render_chat(context, chat)
    {assistant_update_count(context) >= 2, context}
  end

  @impl true
  def second_codex_response_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=assistant-message]")
    |> Enum.count()
    |> Kernel.==(2)
  end

  @impl true
  def reject_message(context, message) do
    {:ok, chat} = Chat.submit(context.chat, message)
    render_chat(context, Chat.fail(chat, "Codex is not available."))
  end

  @impl true
  def report_codex_error(context, message) do
    render_chat(context, Chat.fail(context.chat, message))
  end

  @impl true
  def alert_visible?(context, message) do
    context.page
    |> LazyHTML.query("[role=alert]")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(message)
  end

  @impl true
  def reload(context), do: open(context, "/")

  defp render_chat(context, chat) do
    page =
      %{chat: chat, form: Phoenix.Component.to_form(%{"prompt" => ""}, as: :chat)}
      |> BnestAppWeb.ChatLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    context
    |> Map.put(:chat, chat)
    |> Map.put(:page, page)
  end

  defp enabled?(page, selector) do
    page
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("disabled")
    |> Enum.empty?()
  end

  defp assistant_update_count(context) do
    context.page
    |> LazyHTML.query("[data-role=assistant-message]")
    |> Enum.at(-1)
    |> LazyHTML.attribute("data-update-count")
    |> List.first()
    |> String.to_integer()
  end
end
