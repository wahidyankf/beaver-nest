defmodule BnestApp.Behaviour.UnitHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver

  alias BnestApp.Chat
  alias BnestApp.Codex.FixtureModels
  alias Phoenix.HTML.Safe

  @impl true
  def open(context, "/") do
    render_chat(context, Chat.new())
  end

  @impl true
  def brand_logo_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=brand-logo][src='/images/beaver-nest-logo.png']")
    |> Enum.any?()
  end

  @impl true
  def installable_as_app?(_context) do
    BnestAppWeb.Pwa.install_metadata() == %{
      manifest_path: "/manifest.webmanifest",
      service_worker_path: "/service-worker.js",
      icon_paths: ["/images/beaver-nest-192.png", "/images/beaver-nest-512.png"]
    }
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
  def model_selector_lists_all?(context) do
    context.page
    |> LazyHTML.query("[data-role=model-selector] option")
    |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    |> Kernel.==(FixtureModels.display_names())
  end

  @impl true
  def selected_model?(context, display_name) do
    context.page
    |> LazyHTML.query("[data-role=model-selector] option[selected]")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(display_name)
  end

  @impl true
  def effort_selector_lists_supported?(context) do
    model = FixtureModels.fetch_by_id!(context.chat.model)

    context.page
    |> LazyHTML.query("[data-role=effort-selector] option")
    |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    |> Kernel.==(Enum.map(model.supported_reasoning_efforts, &effort_label/1))
  end

  @impl true
  def selected_effort?(context, effort) do
    context.page
    |> LazyHTML.query("[data-role=effort-selector] option[selected]")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(effort)
  end

  @impl true
  def model_selector_available?(context) do
    selector = LazyHTML.query(context.page, "[data-role=model-selector]")
    not Enum.empty?(selector) and selector |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  @impl true
  def model_selector_unavailable?(context),
    do: not model_selector_available?(context)

  @impl true
  def effort_selector_available?(context) do
    selector = LazyHTML.query(context.page, "[data-role=effort-selector]")
    not Enum.empty?(selector) and selector |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  @impl true
  def effort_selector_unavailable?(context),
    do: not effort_selector_available?(context)

  @impl true
  def select_model(context, display_name) do
    model = FixtureModels.fetch_by_display_name!(display_name)

    effort =
      if context.chat.reasoning_effort in model.supported_reasoning_efforts,
        do: context.chat.reasoning_effort,
        else: "medium"

    {:ok, chat} =
      Chat.select_model(context.chat, model.id, effort)

    render_chat(context, chat)
  end

  @impl true
  def select_effort(context, effort) do
    {:ok, chat} = Chat.select_model(context.chat, context.chat.model, String.downcase(effort))
    render_chat(context, chat)
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
  def clear_chat_control_available?(context) do
    controls = LazyHTML.query(context.page, "[data-role=clear-chat]")
    not Enum.empty?(controls) and controls |> LazyHTML.attribute("disabled") |> Enum.empty?()
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
  def submit_with_shift_enter(context, message), do: send_message(context, message)

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
      |> Chat.put_thread_id("fixture-thread")
      |> Chat.update_assistant("Fixture response")
      |> Chat.update_assistant("Fixture response complete.")
      |> Chat.complete()

    {:ok, snapshot} = Chat.snapshot(chat)

    context =
      context
      |> Map.put(:persisted_chat, Jason.encode!(snapshot))
      |> render_chat(chat)

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
  def one_completed_codex_response_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=assistant-message][data-streaming=false]")
    |> Enum.count()
    |> Kernel.==(1)
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
  def reload(%{persisted_chat: encoded} = context) do
    {:ok, snapshot} = Jason.decode(encoded)
    {:ok, chat} = Chat.restore(snapshot)
    render_chat(context, chat)
  end

  @impl true
  def clear_chat(context) do
    context
    |> Map.delete(:persisted_chat)
    |> render_chat(Chat.new(context.chat.model, context.chat.reasoning_effort))
  end

  defp render_chat(context, chat) do
    page =
      %{
        chat: chat,
        models: FixtureModels.all(),
        form: Phoenix.Component.to_form(%{"prompt" => ""}, as: :chat)
      }
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

  defp effort_label("xhigh"), do: "XHigh"
  defp effort_label(effort), do: String.capitalize(effort)
end
