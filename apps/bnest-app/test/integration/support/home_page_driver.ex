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
    has_element?(context.view, "p", text)
  end
end
