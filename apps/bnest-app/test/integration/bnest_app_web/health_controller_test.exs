defmodule BnestAppWeb.HealthControllerTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  test "reports liveness, readiness, and the served release revision", %{conn: conn} do
    live = get(conn, "/health/live")

    assert %{"status" => "live", "revision" => revision} = json_response(live, 200)
    assert get_resp_header(live, "x-bnest-revision") == [revision]

    ready = get(build_conn(), "/health/ready")
    assert %{"status" => "ready", "revision" => ^revision} = json_response(ready, 200)
  end
end
