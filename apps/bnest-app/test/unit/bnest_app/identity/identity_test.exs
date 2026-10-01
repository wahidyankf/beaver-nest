defmodule BnestApp.Identity.IdentityUnitTest do
  # Not async: the active-store tests install the Storage port doubles, which are
  # application-wide configuration, and start the named record repository.
  use ExUnit.Case, async: false

  alias BnestApp.Identity
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.Domain.Authorization
  alias BnestApp.Identity.Domain.Session
  alias BnestApp.Identity.Login
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Identity.Sessions
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.IdentityStore, as: InMemoryIdentityStore
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts

  @username "test-user-identity-unit"
  @password "Synthetic Password 123!"

  # An in-memory store whose operations can be overridden per handle, so a test can make one
  # operation fail or answer with a different record.
  defmodule FaultyStore do
    @moduledoc false

    @behaviour BnestApp.Identity.Ports.IdentityStore

    alias BnestApp.Test.InMemory.IdentityStore, as: InMemoryIdentityStore

    def start(faults),
      do: %{adapter: __MODULE__, inner: InMemoryIdentityStore.start(), faults: faults}

    @impl true
    def new(_records), do: start(%{})

    for {name, arity} <- [
          read_account: 2,
          read_username: 2,
          read_session: 2,
          read_bootstrap: 1,
          put_account: 2,
          put_username: 2,
          put_session: 2,
          put_bootstrap: 2,
          replace_account: 2,
          replace_session: 2,
          replace_bootstrap: 2,
          remove_account: 2,
          remove_username: 2,
          remove_bootstrap: 2,
          empty?: 1,
          lock_key: 1
        ] do
      args = Macro.generate_arguments(arity - 1, __MODULE__)

      @impl true
      def unquote(name)(store, unquote_splicing(args)) do
        case Map.fetch(store.faults, unquote(name)) do
          {:ok, answer} -> answer
          :error -> apply(InMemoryIdentityStore, unquote(name), [store.inner | unquote(args)])
        end
      end
    end
  end

  defp account(username \\ @username, roles \\ ["admin"]),
    do: %{"username" => username, "password" => @password, "roles" => roles}

  defp bootstrapped_store do
    store = InMemoryIdentityStore.start()

    server =
      start_supervised!(
        Supervisor.child_spec({Identity, store: store, name: nil}, id: make_ref())
      )

    {:ok, [account]} = Identity.bootstrap([account()], server)
    %{store: store, server: server, account: account}
  end

  defp flush_message do
    receive do
      message -> message
    after
      0 -> nil
    end
  end

  describe "setup" do
    test "setup_status is open before bootstrap and closed afterwards" do
      server = start_supervised!({Identity, store: InMemoryIdentityStore.start()})

      assert Identity.setup_status() == :open
      {:ok, _created} = Identity.bootstrap([account()])
      assert Identity.setup_status(server) == :closed
    end

    test "bootstrap returns only public account fields and keeps no plaintext" do
      %{store: store, account: account} = bootstrapped_store()

      assert Map.keys(account) |> Enum.sort() ==
               ~w(displayUsername normalizedUsername roles userId)

      assert account["normalizedUsername"] == @username
      refute store |> InMemoryIdentityStore.snapshot() |> inspect() |> String.contains?(@password)
    end

    test "bootstrap sorts roles, keeps the display username, and refuses a second run" do
      store = InMemoryIdentityStore.start()

      assert {:ok, [created]} =
               Bootstrap.create(store, [account("  Test-User-Display ", ~w(parents admin))])

      assert created["roles"] == ~w(admin parents)
      assert created["displayUsername"] == "Test-User-Display"
      assert created["normalizedUsername"] == "test-user-display"
      assert Bootstrap.status(store) == :closed

      assert Bootstrap.create(store, [account("test-user-second")]) == {:error, :closed}
    end

    test "bootstrap refuses invalid account lists before writing anything" do
      store = InMemoryIdentityStore.start()

      assert Bootstrap.create(store, []) == {:error, :accounts_required}
      assert Bootstrap.create(store, :none) == {:error, :accounts_required}
      assert Bootstrap.create(store, [%{"username" => @username}]) == {:error, :invalid_account}
      assert Bootstrap.create(store, [account("-bad")]) == {:error, :invalid_username}
      assert Bootstrap.create(store, [account(@username, ["owner"])]) == {:error, :invalid_roles}

      assert Bootstrap.create(store, [account(@username, ["admin", "admin"])]) ==
               {:error, :invalid_roles}

      assert Bootstrap.create(store, [account(@username, [])]) == {:error, :invalid_roles}

      assert Bootstrap.create(store, [%{account() | "password" => "no digits_"}]) ==
               {:error, :invalid_password}

      assert Bootstrap.create(store, [account(@username, ["children"])]) ==
               {:error, :admin_required}

      assert Bootstrap.create(store, [account("Test-User-A"), account("test-user-a")]) ==
               {:error, :duplicate_username}

      assert InMemoryIdentityStore.snapshot(store) == %{}
      assert Bootstrap.status(store) == :open
    end

    test "setup status reports a pending journal, a conflict, and an unreadable journal" do
      pending = InMemoryIdentityStore.start()
      {:ok, _journal} = IdentityStore.put_bootstrap(pending, %{"state" => "pending"})
      assert Bootstrap.status(pending) == {:error, :recovery_required}

      orphan = InMemoryIdentityStore.start()
      {:ok, _index} = IdentityStore.put_username(orphan, %{"normalizedUsername" => @username})
      assert Bootstrap.status(orphan) == {:error, :conflict}
      assert Bootstrap.create(orphan, [account()]) == {:error, :conflict}

      unreadable = FaultyStore.start(%{read_bootstrap: {:error, :invalid_schema}})
      assert Bootstrap.status(unreadable) == {:error, :invalid_state}
      assert Bootstrap.recover(unreadable) == {:error, :invalid_state}

      assert Identity.init(store: unreadable) ==
               {:stop, {:identity_recovery_failed, :invalid_state}}
    end

    test "a failed account write fails the bootstrap and leaves its journal pending" do
      failing = FaultyStore.start(%{put_username: {:error, :disk_full}})
      assert Bootstrap.create(failing, [account()]) == {:error, :bootstrap_write_failed}
      assert Bootstrap.status(failing) == {:error, :recovery_required}

      # A read-back that differs from the write counts as a failed write too.
      changed = FaultyStore.start(%{read_account: {:ok, %{"userId" => "user-other"}}})
      assert Bootstrap.create(changed, [account()]) == {:error, :bootstrap_write_failed}
    end
  end

  describe "recovery" do
    test "recovery rolls back a pending bootstrap's matching records" do
      store = FaultyStore.start(%{replace_bootstrap: {:error, :disk_full}})
      assert Bootstrap.create(store, [account()]) == {:error, :disk_full}
      assert Bootstrap.status(store) == {:error, :recovery_required}

      assert Bootstrap.recover(store) == :ok
      assert Bootstrap.status(store) == :open
      assert InMemoryIdentityStore.snapshot(store.inner) == %{}

      # Recovery is a no-op without a journal, and with a closed one.
      assert Bootstrap.recover(store) == :ok
      closed = InMemoryIdentityStore.start()
      {:ok, _created} = Bootstrap.create(closed, [account()])
      assert Bootstrap.recover(closed) == :ok
      assert Bootstrap.status(closed) == :closed
    end

    test "recovery skips records that are already gone" do
      store = FaultyStore.start(%{replace_bootstrap: {:error, :disk_full}})
      {:error, :disk_full} = Bootstrap.create(store, [account()])
      {:ok, journal} = IdentityStore.read_bootstrap(store)
      [%{"userId" => user_id, "normalizedUsername" => username}] = journal["accounts"]
      {:ok, stored_account} = IdentityStore.read_account(store, user_id)
      {:ok, stored_index} = IdentityStore.read_username(store, username)
      :ok = IdentityStore.remove_account(store, stored_account)
      :ok = IdentityStore.remove_username(store, stored_index)

      assert Bootstrap.recover(store) == :ok
      assert IdentityStore.read_bootstrap(store) == {:error, :missing}
    end

    test "recovery refuses to remove an account or index that changed since the journal" do
      for {kind, change} <- [
            {:account, &Map.put(&1, "displayUsername", "Changed")},
            {:username_index, &Map.put(&1, "userId", "user-other")}
          ] do
        store = FaultyStore.start(%{replace_bootstrap: {:error, :disk_full}})
        {:error, :disk_full} = Bootstrap.create(store, [account()])
        {:ok, journal} = IdentityStore.read_bootstrap(store)
        [%{"userId" => user_id, "normalizedUsername" => username}] = journal["accounts"]

        changed =
          case kind do
            :account ->
              {:ok, stored} = IdentityStore.read_account(store, user_id)
              stored |> change.() |> then(&IdentityStore.replace_account(store, &1))

            :username_index ->
              {:ok, stored} = IdentityStore.read_username(store, username)
              :ok = IdentityStore.remove_username(store, stored)
              IdentityStore.put_username(store, change.(stored))
          end

        assert {:ok, _changed} = changed
        assert Bootstrap.recover(store) == {:error, :changed}
        assert {:ok, ^journal} = IdentityStore.read_bootstrap(store)
      end
    end

    test "recovery stops on an unreadable account or index" do
      for fault <- [:read_account, :read_username] do
        store = FaultyStore.start(%{replace_bootstrap: {:error, :disk_full}})
        {:error, :disk_full} = Bootstrap.create(store, [account()])
        unreadable = %{store | faults: %{fault => {:error, :invalid_schema}}}

        assert Bootstrap.recover(unreadable) == {:error, :invalid_state}
      end
    end
  end

  describe "login and sessions" do
    test "login issues a session token the store can resolve back to the account" do
      %{store: store, account: account} = bootstrapped_store()

      assert {:ok, token} = Login.authenticate(store, @username, @password)
      assert {:ok, ^account} = Sessions.current_user(store, token)

      assert {:ok, %{"revokedAt" => nil, "userId" => user_id}} =
               IdentityStore.read_session(store, Session.digest(token))

      assert user_id == account["userId"]
      refute store |> InMemoryIdentityStore.snapshot() |> inspect() |> String.contains?(token)
    end

    test "login accepts the display form of a username" do
      %{store: store} = bootstrapped_store()

      assert {:ok, _token} =
               Login.authenticate(store, "  " <> String.upcase(@username) <> "  ", @password)
    end

    test "login rejects wrong passwords, unknown and invalid usernames alike" do
      %{store: store} = bootstrapped_store()

      for {username, password} <- [
            {@username, "Wrong Password 456!"},
            {"test-user-absent", @password},
            {"not a valid username!", @password},
            {nil, @password},
            {@username, nil}
          ] do
        assert Login.authenticate(store, username, password) == {:error, :invalid_credentials}
      end
    end

    test "login fails when no session can be written" do
      %{store: store} = bootstrapped_store()

      busy = FaultyStore.start(%{put_session: {:error, :exists}})
      busy = %{busy | inner: store}
      assert Login.authenticate(busy, @username, @password) == {:error, :invalid_credentials}

      {:ok, %{"userId" => user_id}} = IdentityStore.read_username(store, @username)
      assert Sessions.create(busy, user_id) == {:error, :session_write_failed}

      broken = %{busy | faults: %{put_session: {:error, :disk_full}}}
      assert Sessions.create(broken, user_id) == {:error, :session_write_failed}
    end

    test "a session whose account is gone no longer authenticates" do
      %{store: store, account: account} = bootstrapped_store()
      {:ok, token} = Login.authenticate(store, @username, @password)
      {:ok, stored} = IdentityStore.read_account(store, account["userId"])
      :ok = IdentityStore.remove_account(store, stored)

      assert Sessions.current_user(store, token) == {:error, :unauthenticated}
      assert Sessions.current_user(store, nil) == {:error, :unauthenticated}
      assert Sessions.revoke(store, nil) == {:error, :unauthenticated}
    end

    test "logout revokes the session and disconnects its digest" do
      %{store: store} = bootstrapped_store()
      {:ok, token} = Login.authenticate(store, @username, @password)
      digest = Session.digest(token)

      assert Login.revoke(store, token) == :ok
      assert_received {:session_disconnected, ^digest}
      assert Sessions.current_user(store, token) == {:error, :unauthenticated}
    end

    test "logout stays silent for a token that was never issued" do
      %{store: store} = bootstrapped_store()

      assert Login.revoke(store, "never-issued-token") == :ok
      refute_received {:session_disconnected, _digest}
    end

    test "logout of an already revoked token disconnects only once" do
      %{store: store} = bootstrapped_store()
      {:ok, token} = Login.authenticate(store, @username, @password)

      assert Login.revoke(store, token) == :ok
      assert_received {:session_disconnected, _digest}

      assert Login.revoke(store, token) == :ok
      refute_received {:session_disconnected, _digest}
    end
  end

  describe "facade over the active record store" do
    setup do
      previous = StoragePorts.install()
      on_exit(fn -> StoragePorts.restore(previous) end)
      records = InMemoryRecordBackend.start()
      start_supervised!({Records, store: records})

      server =
        start_supervised!(Supervisor.child_spec({Identity, name: nil}, id: make_ref()))

      {:ok, [account]} = Identity.bootstrap([account()], server)
      %{records: records, server: server, account: account}
    end

    test "bootstraps into the record store Storage reports as active", %{
      records: records,
      server: server,
      account: account
    } do
      assert Identity.setup_status(server) == :closed

      assert {:ok, %{"displayUsername" => @username}} =
               InMemoryRecordBackend.read(records, :account, account["userId"])
    end

    test "login, current user, and logout work end to end", %{account: account} do
      assert {:ok, token} = Identity.login(@username, @password)
      assert Identity.current_user(token) == {:ok, account}
      digest = Identity.session_digest(token)

      # Deactivation comes before revocation, so a failed deactivation leaves the session.
      assert Identity.logout(token) == :ok
      assert flush_message() == {:subscription_revoked, account["userId"], digest}
      assert flush_message() == {:session_disconnected, digest}
      assert Identity.current_user(token) == {:error, :unauthenticated}

      assert Identity.logout(token) == :ok
      assert flush_message() == nil
      assert Identity.login(@username, "Wrong Password 456!") == {:error, :invalid_credentials}
    end

    test "reads public account fields and the live display name", %{account: account} do
      user_id = account["userId"]

      assert Identity.account(user_id) == {:ok, account}
      assert Identity.account("user-absent") == {:error, :missing}
      assert Identity.display_name_for(user_id) == @username
      assert Identity.display_name_for("user-absent") == nil
    end
  end

  test "authorize delegates to the authorization policy" do
    account = %{"userId" => "user-1", "roles" => ["parents"]}

    assert Identity.authorize(account, :use_chat, "user-1") ==
             Authorization.allow?(account, :use_chat, "user-1")

    refute Identity.authorize(account, :read_own_chat, "user-1")
  end

  test "names its configured adapters and benchmarks the configured hasher" do
    assert Identity.adapter(:credential_hasher) == BnestApp.Test.InMemory.CredentialHasher
    assert Identity.benchmark_hasher() == {:ok, 0}
    assert_raise KeyError, fn -> Identity.adapter(:unknown) end
  end
end
