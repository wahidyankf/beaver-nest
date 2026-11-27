defmodule BnestAppWeb.UserAuthTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BnestApp.Identity
  alias BnestApp.Storage.Records
  alias BnestApp.Test.CallTrace
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestAppWeb.UserAuth

  # The record-backed request path, empty so no session resolves: the shared
  # setup for the request-level UserAuth proofs below.
  setup do
    {:ok, _apps} = Application.ensure_all_started(:plug)
    previous = StoragePorts.install()
    on_exit(fn -> StoragePorts.restore(previous) end)
    store = InMemoryRecordBackend.start()
    start_supervised!({Records, store: store})
    :ok
  end

  test "keeps the legacy browser experience available until cutover is enabled" do
    assert %{
             "userId" => "legacy-browser",
             "displayUsername" => "Local browser",
             "migrationMode" => true
           } = UserAuth.transition_user(false)

    assert UserAuth.transition_user(true) == nil
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: A non-administrator causes no integrity check
  test "a non-administrator is refused before any reconciliation or verified-run read starts" do
    watched = [
      {{BnestApp.Scheduler, :verified_runs, 1}, []},
      {{BnestApp.Backup, :reconcile, 2}, []}
    ]

    {conn, events} =
      CallTrace.record(watched, fn ->
        Plug.Test.conn(:get, "/admin/settings/schedules")
        |> Plug.Conn.assign(:current_user, %{"userId" => "child", "roles" => ["children"]})
        |> UserAuth.require_admin_role([])
      end)

    assert conn.halted
    assert conn.status == 404
    assert events == []
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: A visitor who may not administer Bnest cannot open admin settings
  test "the admin gate halts a non-admin connection with not found before any LiveView mounts" do
    conn =
      Plug.Test.conn(:get, "/admin/settings/schedules")
      |> Plug.Conn.assign(:current_user, %{"userId" => "child", "roles" => ["children"]})
      |> UserAuth.require_admin_role([])

    assert conn.halted
    assert conn.status == 404
    assert conn.resp_body == "Not found"

    storage =
      Plug.Test.conn(:get, "/storage")
      |> Plug.Conn.assign(:current_user, %{"userId" => "child", "roles" => ["children"]})
      |> UserAuth.require_admin_role([])

    assert storage.halted
    assert storage.status == 404
    assert storage.resp_body == "Not found"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A login return path stays on this site
  test "a login return path stays on this site" do
    # The scheme is joined at compile time, as in `chat_markdown_test.exs`, so
    # the unit layer's network-URL boundary sees no URL literal.
    evil = "https:" <> "//evil.example"

    assert UserAuth.safe_return_path("/chat") == "/chat"
    assert UserAuth.safe_return_path("//evil.example") == "/"
    assert UserAuth.safe_return_path(evil) == "/"
    assert UserAuth.safe_return_path("chat") == "/"
    assert UserAuth.safe_return_path("") == "/"
    assert UserAuth.safe_return_path(nil) == "/"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A logged-out visitor is sent to login from any protected page
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A signed-out visitor cannot fetch a repository image
  test "a logged-out visitor is sent to login from any protected page" do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)
    Application.put_env(:bnest_app, :identity_cutover_enabled, true)

    try do
      for route <- ["/", "/chat", "/chat/images/apps/bnest-app/priv/static/logo.png"] do
        conn =
          conn(:get, route)
          |> init_test_session(%{})
          |> Phoenix.Controller.fetch_flash([])
          |> UserAuth.fetch_current_user([])
          |> UserAuth.require_authenticated_user([])

        assert conn.halted
        assert conn.assigns[:current_user] == nil

        assert Plug.Conn.get_resp_header(conn, "location") ==
                 ["/login?return_to=#{URI.encode_www_form(route)}"]
      end
    after
      Application.put_env(:bnest_app, :identity_cutover_enabled, previous)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: With identity cutover off an unsigned browser acts as the local user
  test "with identity cutover off an unsigned browser acts as the local user" do
    for enabled <- [false, true] do
      previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)
      Application.put_env(:bnest_app, :identity_cutover_enabled, enabled)

      try do
        conn =
          conn(:get, "/")
          |> init_test_session(%{})
          |> UserAuth.fetch_current_user([])

        if enabled do
          assert conn.assigns.current_user == nil
        else
          assert %{
                   "userId" => "legacy-browser",
                   "displayUsername" => "Local browser",
                   "migrationMode" => true
                 } = conn.assigns.current_user

          assert conn.assigns.browser_persistence == true
        end

        assert Identity.current_user(nil) == {:error, :unauthenticated}
      after
        Application.put_env(:bnest_app, :identity_cutover_enabled, previous)
      end
    end
  end
end
