defmodule BnestAppWeb.ConnCaseFreshDatabaseTest do
  # The ConnCase contract (ADR 001, sections 1 and 8 T9): every integration test that uses ConnCase runs on its own
  # test instance. Its accounts are seeded through the production facades, their usernames carry the instance short
  # id, and the helpers return the seeded names. Nothing is left in the shared run base.
  use BnestAppWeb.ConnCase, async: false

  @moduletag :conn_case

  alias BnestApp.Identity
  alias BnestApp.TestInstance

  test "the test runs on its own current instance, with its seeded accounts", %{
    instance: instance,
    accounts: accounts
  } do
    assert TestInstance.state().instance_id == instance.instance_id

    short = String.slice(instance.instance_id, 0, 8)
    assert ["test-user-integration-" <> ^short, "test-user-other-" <> ^short] = accounts
  end

  test "the helpers return the seeded admin, and that admin can log in" do
    {username, password} = test_credentials()

    short = String.slice(TestInstance.state().instance_id, 0, 8)
    assert username == "test-user-integration-#{short}"
    assert {:ok, _token} = Identity.login(username, password)
  end

  test "an authenticated connection carries the identity cookie", %{conn: conn} do
    token = conn |> authenticated_conn() |> fetch_cookies() |> Map.fetch!(:req_cookies)
    assert {:ok, _user} = Identity.current_user(token["_bnest_identity"])
  end

  test "a scenario identity is seeded into the current instance and logs in", %{conn: conn} do
    {conn, identity} = scenario_authenticated_conn(conn, "conn-case-probe")

    short = String.slice(TestInstance.state().instance_id, 0, 8)
    assert identity.username =~ ~r/\Atest-user-bdd-[0-9a-f]{8}-#{short}\z/
    assert {:ok, _token} = Identity.login(identity.username, identity.password)
    assert %{"_bnest_identity" => _token} = fetch_cookies(conn).req_cookies
  end

  test "the shared run base holds no account, user, or database" do
    assert TestInstance.base_audit() == :ok
  end
end
