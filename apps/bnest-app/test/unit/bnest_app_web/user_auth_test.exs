defmodule BnestAppWeb.UserAuthTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.UserAuth

  test "keeps the legacy browser experience available until cutover is enabled" do
    assert %{
             "userId" => "legacy-browser",
             "displayUsername" => "Local browser",
             "migrationMode" => true
           } = UserAuth.transition_user(false)

    assert UserAuth.transition_user(true) == nil
  end

  test "the admin gate halts a non-admin connection with not found before any LiveView mounts" do
    conn =
      Plug.Test.conn(:get, "/admin/settings/schedules")
      |> Plug.Conn.assign(:current_user, %{"userId" => "child", "roles" => ["children"]})
      |> UserAuth.require_admin_role([])

    assert conn.halted
    assert conn.status == 404
    assert conn.resp_body == "Not found"
  end
end
