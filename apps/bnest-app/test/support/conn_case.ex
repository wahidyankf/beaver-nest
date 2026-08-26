defmodule BnestAppWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use BnestAppWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias BnestApp.DataRepository
  alias BnestApp.Identity
  alias BnestApp.Identity.CredentialVerifier
  alias BnestApp.Identity.FileStore

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
        ensure_test_account!()
        {:ok, conn: conn}

      {"integration", _missing} ->
        ensure_test_account!()
        scenario_key = "#{inspect(tags[:module])}:#{tags[:test]}"
        {conn, identity} = scenario_authenticated_conn(conn, scenario_key)
        {:ok, conn: conn, test_identity: identity}

      {_unit_or_other, _tag} ->
        {:ok, conn: conn}
    end
  end

  @test_username "test-user-integration"
  @test_password "Synthetic Integration Password 123!"

  def authenticated_conn(conn) do
    ensure_test_account!()
    {:ok, token} = Identity.login(@test_username, @test_password)
    Plug.Test.put_req_cookie(conn, "_bnest_identity", token)
  end

  def scenario_authenticated_conn(conn, scenario_key) do
    identity = scenario_identity!(scenario_key)
    {:ok, token} = Identity.login(identity.username, identity.password)
    {Plug.Test.put_req_cookie(conn, "_bnest_identity", token), identity}
  end

  def test_credentials do
    ensure_test_account!()
    {@test_username, @test_password}
  end

  defp scenario_identity!(scenario_key) do
    suffix =
      :crypto.hash(:sha256, scenario_key)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 12)

    identity = %{
      username: "test-user-bdd-#{suffix}",
      password: "Synthetic BDD Password #{suffix}!",
      user_id: "user-test-bdd-#{suffix}"
    }

    store = DataRepository.store()

    case FileStore.read_account(store, identity.user_id) do
      {:ok, _existing} ->
        identity

      {:error, :missing} ->
        {:ok, verifier} = CredentialVerifier.hash(identity.password)
        timestamp = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

        account = %{
          "schemaVersion" => 1,
          "recordType" => "account",
          "userId" => identity.user_id,
          "displayUsername" => identity.username,
          "normalizedUsername" => identity.username,
          "roles" => ["admin", "children", "parents"],
          "passwordVerifier" => verifier,
          "createdAt" => timestamp
        }

        index = %{
          "schemaVersion" => 1,
          "recordType" => "username-index",
          "normalizedUsername" => identity.username,
          "userId" => identity.user_id
        }

        {:ok, ^account} = FileStore.put_account(store, account)
        {:ok, ^index} = FileStore.put_username(store, index)
        identity
    end
  end

  def ensure_test_account! do
    case Identity.setup_status() do
      :open ->
        accounts = [
          %{
            "username" => @test_username,
            "password" => @test_password,
            "roles" => ["admin", "parents"]
          },
          %{
            "username" => "test-user-other",
            "password" => @test_password,
            "roles" => ["children"]
          }
        ]

        case Identity.bootstrap(accounts) do
          {:ok, _users} -> :ok
          {:error, :closed} -> :ok
        end

      :closed ->
        :ok
    end
  end
end
