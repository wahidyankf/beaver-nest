defmodule BnestAppWeb.HelloLiveTest do
  use BnestAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the greeting", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "Hello, World!"
    assert render(view) =~ "Welcome to Beaver Nest."
  end
end
