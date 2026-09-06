defmodule BnestApp.IdentityUnitTest do
  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.MemoryBackend
  alias BnestApp.Identity
  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.Login
  alias BnestApp.Identity.Session

  @username "test-user-identity-unit"
  @password "Synthetic Password 123!"

  # The store is a memory backend, so FileStore and Session reach their real logic through
  # DataRepository.Backend without touching a disk.
  defmodule NotifierSpy do
    @moduledoc false

    def broadcast(topic, event, payload) do
      send(self(), {:broadcast, topic, event, payload})
      :ok
    end
  end

  defp bootstrapped_store do
    store = MemoryBackend.start()

    server =
      start_supervised!(
        Supervisor.child_spec({Identity, store: store, name: nil}, id: make_ref())
      )

    {:ok, [account]} =
      Identity.bootstrap(
        [%{"username" => @username, "password" => @password, "roles" => ["admin"]}],
        server
      )

    %{store: store, server: server, account: account}
  end

  test "setup_status is open before bootstrap and closed afterwards" do
    store = MemoryBackend.start()

    server =
      start_supervised!(
        Supervisor.child_spec({Identity, store: store, name: nil}, id: make_ref())
      )

    assert Identity.setup_status(server) == :open

    {:ok, _created} =
      Identity.bootstrap(
        [%{"username" => @username, "password" => @password, "roles" => ["admin"]}],
        server
      )

    assert Identity.setup_status(server) == :closed
  end

  test "bootstrap returns only public account fields" do
    %{account: account} = bootstrapped_store()

    assert Map.keys(account) |> Enum.sort() ==
             ~w(displayUsername normalizedUsername roles userId)

    assert account["normalizedUsername"] == @username
  end

  test "bootstrap refuses a second run once setup closed" do
    %{server: server} = bootstrapped_store()

    assert Identity.bootstrap(
             [%{"username" => "test-user-second", "password" => @password, "roles" => ["admin"]}],
             server
           ) == {:error, :closed}
  end

  test "login issues a session token the store can resolve back to the account" do
    %{store: store, account: account} = bootstrapped_store()

    assert {:ok, token} = Login.authenticate(store, @username, @password)
    assert {:ok, resolved} = Session.current_user(store, token)
    assert resolved["userId"] == account["userId"]
  end

  test "login accepts the display form of a username" do
    %{store: store} = bootstrapped_store()

    assert {:ok, _token} =
             Login.authenticate(store, "  " <> String.upcase(@username) <> "  ", @password)
  end

  test "login rejects a wrong password without revealing the account exists" do
    %{store: store} = bootstrapped_store()

    assert Login.authenticate(store, @username, "Wrong Password 456!") ==
             {:error, :invalid_credentials}
  end

  test "login rejects an unknown username" do
    %{store: store} = bootstrapped_store()

    assert Login.authenticate(store, "test-user-absent", @password) ==
             {:error, :invalid_credentials}
  end

  test "login rejects a structurally invalid username" do
    %{store: store} = bootstrapped_store()

    assert Login.authenticate(store, "not a valid username!", @password) ==
             {:error, :invalid_credentials}
  end

  test "logout revokes the session and broadcasts a disconnect for its digest" do
    %{store: store} = bootstrapped_store()
    {:ok, token} = Login.authenticate(store, @username, @password)
    digest = Session.digest(token)

    assert Login.revoke(store, token, NotifierSpy) == :ok
    assert_received {:broadcast, topic, "disconnect", %{}}
    assert topic == "identity:#{digest}"

    assert Session.current_user(store, token) == {:error, :unauthenticated}
  end

  test "logout stays silent for a token that was never issued" do
    %{store: store} = bootstrapped_store()

    assert Login.revoke(store, "never-issued-token", NotifierSpy) == :ok
    refute_received {:broadcast, _topic, _event, _payload}
  end

  test "logout of an already revoked token broadcasts only once" do
    %{store: store} = bootstrapped_store()
    {:ok, token} = Login.authenticate(store, @username, @password)

    assert Login.revoke(store, token, NotifierSpy) == :ok
    assert_received {:broadcast, _topic, _event, _payload}

    assert Login.revoke(store, token, NotifierSpy) == :ok
    refute_received {:broadcast, _topic, _event, _payload}
  end

  test "authorize delegates to the authorization policy" do
    account = %{"userId" => "user-1", "roles" => ["parents"]}

    assert Identity.authorize(account, :read_own_chat, "user-1") ==
             Authorization.allow?(account, :read_own_chat, "user-1")
  end
end
