defmodule BnestApp.Behaviour.IntegrationHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver
  @endpoint BnestAppWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.Codex.FixtureModels

  @impl true
  def open(%{conn: conn} = context, route) do
    {:ok, view, _html} = live(conn, route)
    Map.put(context, :view, view)
  end

  @impl true
  def brand_logo_visible?(context) do
    has_element?(context.view, "[data-role=brand-logo][src='/images/beaver-nest-logo.png']")
  end

  @impl true
  def installable_as_app?(context) do
    manifest_response = get(context.conn, "/manifest.webmanifest")

    with 200 <- manifest_response.status,
         {:ok, manifest} <- Jason.decode(manifest_response.resp_body),
         "Beaver Nest" <- manifest["name"],
         "standalone" <- manifest["display"],
         [
           %{"src" => "/images/beaver-nest-192.png", "sizes" => "192x192"},
           %{"src" => "/images/beaver-nest-512.png", "sizes" => "512x512"}
         ] <- manifest["icons"],
         200 <- get(context.conn, "/service-worker.js").status,
         200 <- get(context.conn, "/images/beaver-nest-192.png").status,
         200 <- get(context.conn, "/images/beaver-nest-512.png").status do
      true
    else
      _not_installable -> false
    end
  end

  @impl true
  def heading_visible?(context, heading) do
    has_element?(context.view, "h1", heading)
  end

  @impl true
  def text_visible?(context, text) do
    has_element?(context.view, ".model-badge", text)
  end

  @impl true
  def model_selector_lists_all?(context) do
    Enum.all?(FixtureModels.all(), fn model ->
      has_element?(
        context.view,
        "[data-role=model-selector] option[value='#{model.id}']",
        model.display_name
      )
    end)
  end

  @impl true
  def selected_model?(context, display_name) do
    model = FixtureModels.fetch_by_display_name!(display_name)
    has_element?(context.view, "[data-role=model-selector] option[value='#{model.id}'][selected]")
  end

  @impl true
  def effort_selector_lists_supported?(context) do
    selected_model_id =
      context.view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=model-selector] option[selected]")
      |> LazyHTML.attribute("value")
      |> List.first()

    model = FixtureModels.fetch_by_id!(selected_model_id)

    Enum.all?(model.supported_reasoning_efforts, fn effort ->
      has_element?(
        context.view,
        "[data-role=effort-selector] option[value='#{effort}']",
        effort_label(effort)
      )
    end) and
      context.view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=effort-selector] option")
      |> Enum.count()
      |> Kernel.==(length(model.supported_reasoning_efforts))
  end

  @impl true
  def selected_effort?(context, effort) do
    has_element?(
      context.view,
      "[data-role=effort-selector] option[value='#{String.downcase(effort)}'][selected]"
    )
  end

  @impl true
  def model_selector_available?(context) do
    has_element?(context.view, "[data-role=model-selector]:not([disabled])")
  end

  @impl true
  def model_selector_unavailable?(context) do
    has_element?(context.view, "[data-role=model-selector][disabled]")
  end

  @impl true
  def effort_selector_available?(context) do
    has_element?(context.view, "[data-role=effort-selector]:not([disabled])")
  end

  @impl true
  def effort_selector_unavailable?(context) do
    has_element?(context.view, "[data-role=effort-selector][disabled]")
  end

  @impl true
  def select_model(context, display_name) do
    model = FixtureModels.fetch_by_display_name!(display_name)
    render_change(context.view, "select_model", %{"model" => model.id})
    snapshot = await_push_event(context.view, "persist-chat")
    Map.put(context, :persisted_chat, Jason.encode!(snapshot))
  end

  @impl true
  def select_effort(context, effort) do
    render_change(context.view, "select_effort", %{
      "reasoning_effort" => String.downcase(effort)
    })

    snapshot = await_push_event(context.view, "persist-chat")
    Map.put(context, :persisted_chat, Jason.encode!(snapshot))
  end

  @impl true
  def conversation_empty?(context) do
    not has_element?(context.view, "[data-role=message]")
  end

  @impl true
  def composer_available?(context) do
    not has_element?(context.view, "textarea[disabled]") and
      not has_element?(context.view, ".send-button[disabled]")
  end

  @impl true
  def composer_unavailable?(context) do
    has_element?(context.view, "textarea[disabled]") and
      has_element?(context.view, ".send-button[disabled]")
  end

  @impl true
  def clear_chat_control_available?(context) do
    has_element?(context.view, "[data-role=clear-chat]:not([disabled])")
  end

  @impl true
  def attempt_empty_message(context) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => "   "}})
    context
  end

  @impl true
  def send_message(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
    context
  end

  @impl true
  def submit_with_shift_enter(context, message), do: send_message(context, message)

  @impl true
  def attempt_message_before_finished(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
    context
  end

  @impl true
  def visitor_message_visible?(context, message) do
    has_element?(context.view, "[data-role=user-message]", message)
  end

  @impl true
  def visitor_message_absent?(context, message) do
    not visitor_message_visible?(context, message)
  end

  @impl true
  def stream_codex_response(context) do
    session = context.view.pid
    send(context.view.pid, {:codex, session, {:thread_started, "fixture-thread"}})
    send(context.view.pid, {:codex, session, {:assistant_update, "Fixture response"}})
    send(context.view.pid, {:codex, session, {:assistant_update, "Fixture response complete."}})
    send(context.view.pid, {:codex, session, :turn_completed})

    snapshot = await_push_event(context.view, "persist-chat")

    streamed? =
      context.view
      |> element("[data-role=message]:last-child [data-role=assistant-message]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-update-count]")
      |> LazyHTML.attribute("data-update-count")
      |> List.first()
      |> then(&(&1 && String.to_integer(&1) >= 2))

    {streamed?, Map.put(context, :persisted_chat, Jason.encode!(snapshot))}
  end

  @impl true
  def second_codex_response_visible?(context) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=assistant-message]")
    |> Enum.count()
    |> Kernel.==(2)
  end

  @impl true
  def one_completed_codex_response_visible?(context) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=assistant-message][data-streaming=false]")
    |> Enum.count()
    |> Kernel.==(1)
  end

  @impl true
  def reject_message(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
    context
  end

  @impl true
  def report_codex_error(context, message) do
    send(context.view.pid, {:codex, context.view.pid, {:error, message}})
    render(context.view)
    context
  end

  @impl true
  def alert_visible?(context, message) do
    has_element?(context.view, "[role=alert]", message)
  end

  @impl true
  def reload(%{conn: conn, persisted_chat: persisted_chat} = context) do
    conn = put_connect_params(conn, %{"chat" => persisted_chat})
    {:ok, view, _html} = live(conn, "/")
    Map.put(context, :view, view)
  end

  @impl true
  def clear_chat(context) do
    context.view
    |> element("[data-role=clear-chat]")
    |> render_click()

    %{} = await_push_event(context.view, "clear-chat-storage")
    Map.delete(context, :persisted_chat)
  end

  defp await_push_event(view, event) do
    %{proxy: {ref, _topic, _}} = view

    receive do
      {^ref, {:push_event, ^event, payload}} -> payload
    end
  end

  defp effort_label("xhigh"), do: "XHigh"
  defp effort_label(effort), do: String.capitalize(effort)
end
