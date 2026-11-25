defmodule BnestAppWeb.PageHTMLTest do
  use BnestAppWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  # The home page no longer navigates to the Sifat Allah mission: the mission stays
  # reachable only through its direct /apps/sifat-allah URL.
  @current_user %{
    "displayUsername" => "test-user-unit",
    "migrationMode" => false,
    "roles" => [],
    "userId" => "test-user-unit"
  }

  test "home renders no Sifat Allah entry but keeps the chat entry" do
    html =
      render_to_string(BnestAppWeb.PageHTML, "home", "html",
        flash: %{},
        current_user: @current_user
      )

    assert html =~ ~s(href="/chat")
    refute html =~ "sifat-allah"
    refute html =~ "Misi hafal 40 sifat Allah"
  end

  test "home always renders the family chat entry" do
    html =
      render_to_string(BnestAppWeb.PageHTML, "home", "html",
        flash: %{},
        current_user: @current_user
      )

    assert html =~ ~s(href="/family-chat")
    assert html =~ ~s(data-role="family-chat-entry")
  end
end
