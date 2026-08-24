defmodule BnestApp.Behaviour.IntegrationHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver
  @endpoint BnestAppWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @impl true
  def open(%{conn: conn} = context, route) do
    {:ok, view, _html} = live(conn, route)
    Map.put(context, :view, view)
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
    send(context.view.pid, {:codex, {:assistant_update, "Fixture response"}})
    send(context.view.pid, {:codex, {:assistant_update, "Fixture response complete."}})
    send(context.view.pid, {:codex, :turn_completed})

    streamed? =
      context.view
      |> element("[data-role=message]:last-child [data-role=assistant-message]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-update-count]")
      |> LazyHTML.attribute("data-update-count")
      |> List.first()
      |> then(&(&1 && String.to_integer(&1) >= 2))

    {streamed?, context}
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
  def reject_message(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
    context
  end

  @impl true
  def report_codex_error(context, message) do
    send(context.view.pid, {:codex, {:error, message}})
    render(context.view)
    context
  end

  @impl true
  def alert_visible?(context, message) do
    has_element?(context.view, "[role=alert]", message)
  end

  @impl true
  def reload(%{conn: conn} = context) do
    {:ok, view, _html} = live(conn, "/")
    Map.put(context, :view, view)
  end
end
