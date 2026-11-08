defmodule BnestAppWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also import other functionality to make it easier to build common data
  structures and query the data layer.

  In the integration layer every test runs on its own fresh database (ADR 001, section 1): the setup spawns a test
  instance through `BnestApp.FreshDatabaseCase`, seeds the standard accounts into it, and drops it when the test
  ends. The helpers return the usernames the seed created, so no test hard-codes a username. A test that is not
  integration (the unit layer) gets only a connection and touches no storage.

  The case is serial (`async: false`), because one test instance is current at a time.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  use ExUnit.CaseTemplate

  alias BnestApp.FreshDatabaseCase
  alias BnestApp.Identity
  alias BnestApp.TestInstance

  using do
    quote do
      # The default endpoint for testing
      @endpoint BnestAppWeb.Endpoint

      use BnestAppWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import BnestAppWeb.ConnCase
    end
  end

  setup tags do
    conn = Phoenix.ConnTest.build_conn()

    case {System.get_env("BNEST_TEST_LAYER"), tags[:unauthenticated]} do
      {"integration", true} ->
        {:ok,
         FreshDatabaseCase.fresh_database!(tags, FreshDatabaseCase.standard_accounts()) ++
           [conn: conn]}

      {"integration", _authenticated} ->
        setup = FreshDatabaseCase.fresh_database!(tags, FreshDatabaseCase.standard_accounts())
        {conn, identity} = scenario_authenticated_conn(conn, scenario_key(tags))
        {:ok, setup ++ [conn: conn, test_identity: identity]}

      {_unit_or_other, _tag} ->
        {:ok, conn: conn}
    end
  end

  defp scenario_key(tags), do: "#{inspect(tags[:module])}:#{tags[:test]}"

  @doc "A connection that carries the seeded admin's identity cookie, logged in through the production login."
  def authenticated_conn(conn) do
    {username, password} = test_credentials()
    {:ok, token} = Identity.login(username, password)
    Plug.Test.put_req_cookie(conn, "_bnest_identity", token)
  end

  @doc """
  A connection that carries a scenario's own identity, seeded into the current instance under a key derived from
  the scenario and its roles. The same key returns the same account. Returns the connection and the identity
  (`username`, `password`, `user_id`).
  """
  def scenario_authenticated_conn(conn, scenario_key, roles \\ ["admin"]) do
    identity = scenario_identity!(scenario_key, roles)
    {:ok, token} = Identity.login(identity.username, identity.password)
    {Plug.Test.put_req_cookie(conn, "_bnest_identity", token), identity}
  end

  @doc "The seeded admin's username and its password, as the current instance seeded them."
  def test_credentials do
    {seeded_username!("integration"), FreshDatabaseCase.account_password()}
  end

  defp seeded_username!(name) do
    case FreshDatabaseCase.default_account(name) do
      %{username: username} -> username
      nil -> raise "the current test instance has no seeded #{name} account"
    end
  end

  # The scenario's account is seeded under its own key, so a later call with the same key finds it again. The
  # username has the same shape as the default accounts: `test-user-` prefix, a `bdd` segment, the hash and the
  # instance short id, which keeps it within the 32-character username limit.
  defp scenario_identity!(scenario_key, roles) do
    instance = TestInstance.state() || raise "a scenario identity needs the test's instance"

    suffix =
      :crypto.hash(:sha256, "#{scenario_key}:#{Enum.join(roles, ",")}")
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    short = String.slice(instance.instance_id, 0, 8)

    seed = %{
      "accounts" => [
        %{
          "username" => "test-user-bdd-#{suffix}-#{short}",
          "password" => FreshDatabaseCase.account_password(),
          "roles" => roles
        }
      ]
    }

    case TestInstance.seed_current(instance.instance_id, "bdd-" <> suffix, seed) do
      {:ok, %{accounts: [account]}} ->
        %{
          username: account.username,
          password: FreshDatabaseCase.account_password(),
          user_id: account.user_id
        }

      other ->
        raise "the scenario identity could not be seeded: #{inspect(other)}"
    end
  end
end
