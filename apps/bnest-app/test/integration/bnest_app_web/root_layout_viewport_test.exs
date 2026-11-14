defmodule BnestAppWeb.RootLayoutViewportTest do
  # ADR 005, Decision 5: a soft keyboard resizes the room's content rather than covering it, so the viewport meta asks
  # for `interactive-widget=resizes-content`. The page's own heights then follow the visible area through `--vvh`.
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  test "the root layout asks the browser to resize the content when a soft keyboard opens" do
    html = html_response(get(build_conn(), "/login"), 200)

    assert html =~
             ~s(<meta name="viewport" content="width=device-width, initial-scale=1, interactive-widget=resizes-content")
  end
end
