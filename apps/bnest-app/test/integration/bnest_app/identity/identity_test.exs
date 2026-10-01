defmodule BnestApp.Identity.IdentityTest do
  use ExUnit.Case, async: false

  alias BnestApp.Identity
  alias BnestApp.Identity.Adapters.Argon2CredentialHasher
  alias BnestApp.Identity.Adapters.RecordIdentityStore
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.Domain.Authorization
  alias BnestApp.Identity.Domain.Credentials
  alias BnestApp.Identity.Domain.Session
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Identity.Sessions
  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("identity-unit")
    on_exit(fn -> if File.exists?(runtime.path), do: TestRuntimeRoot.cleanup!(runtime) end)
    records = FileRecordBackend.new!(runtime.path)
    %{runtime: runtime, records: records, store: RecordIdentityStore.new(records)}
  end

  describe "credentials and usernames" do
    test "normalizes ASCII case and enforces username boundaries" do
      assert {:ok, {"Test-User.Admin", "test-user.admin"}} =
               Credentials.normalize_username("  Test-User.Admin  ")

      assert {:ok, {"a", "a"}} = Credentials.normalize_username("a")

      assert {:ok, {username, username}} =
               Credentials.normalize_username(String.duplicate("a", 32))

      assert {:error, :invalid_username} = Credentials.normalize_username("")

      assert {:error, :invalid_username} =
               Credentials.normalize_username(String.duplicate("a", 33))

      assert {:error, :invalid_username} = Credentials.normalize_username("-family")
      assert {:error, :invalid_username} = Credentials.normalize_username("family/")
      assert {:error, :invalid_username} = Credentials.normalize_username("fámily")
    end

    test "accepts every valid Unicode password with a letter, number, and punctuation without trimming or truncating" do
      assert Credentials.valid_password?("x_1")
      assert Credentials.valid_password?(String.duplicate("é", 129) <> "_1")
      refute Credentials.valid_password?("")
      refute Credentials.valid_password?("password_")
      refute Credentials.valid_password?("password1")
      refute Credentials.valid_password?("123_")

      password = "  Synthetic_password 1  "
      assert {:ok, verifier} = Argon2CredentialHasher.hash(password)
      assert String.starts_with?(verifier, "$argon2id$")
      assert Argon2CredentialHasher.verify(password, verifier)
      refute Argon2CredentialHasher.verify(String.trim(password), verifier)
      refute Argon2CredentialHasher.verify(password, "not-a-verifier")
      refute Argon2CredentialHasher.verify(nil, verifier)
      refute Argon2CredentialHasher.no_user_verify()
    end

    test "benchmarks the configured Argon2id work factor" do
      assert {:ok, elapsed_ms} = Argon2CredentialHasher.benchmark()
      assert is_integer(elapsed_ms) and elapsed_ms >= 0
    end
  end

  describe "one-time bootstrap" do
    test "creates multiple roles and closes permanently without plaintext", %{
      runtime: runtime,
      store: store
    } do
      password = "Synthetic Password 123!"

      assert {:ok, [account]} =
               Bootstrap.create(store, [
                 account("Test-User-Family-Admin", password, ~w(parents admin))
               ])

      assert account["roles"] == ~w(admin parents)
      assert :closed = Bootstrap.status(store)

      assert {:error, :closed} =
               Bootstrap.create(store, [account("test-user-another-admin", password, ["admin"])])

      all_bytes =
        runtime.path
        |> Path.join("**/*.json")
        |> Path.wildcard()
        |> Enum.map_join(&File.read!/1)

      refute all_bytes =~ password
      refute all_bytes =~ "plaintextPassword"
      assert all_bytes =~ "$argon2id$"
    end

    test "rejects duplicate normalized usernames, invalid roles, and a missing admin", %{
      store: store
    } do
      assert {:error, :duplicate_username} =
               Bootstrap.create(store, [
                 account("Test-User-Family-Admin", password(), ["admin"]),
                 account("test-user-family-admin", password(), ["children"])
               ])

      assert :open = Bootstrap.status(store)

      assert {:error, :invalid_roles} =
               Bootstrap.create(store, [
                 account("test-user-family-admin", password(), ["owner"])
               ])

      assert {:error, :admin_required} =
               Bootstrap.create(store, [
                 account("test-user-family-child", password(), ["children"])
               ])
    end

    test "rolls back only matching files from a pending crash", %{store: store} do
      account = valid_account()
      index = valid_index(account)
      journal = pending_journal(account, index)

      assert {:ok, ^journal} = IdentityStore.put_bootstrap(store, journal)
      assert {:ok, ^account} = IdentityStore.put_account(store, account)
      assert {:ok, ^index} = IdentityStore.put_username(store, index)

      assert :ok = Bootstrap.recover(store)
      assert {:error, :missing} = IdentityStore.read_bootstrap(store)
      assert {:error, :missing} = IdentityStore.read_account(store, account["userId"])

      assert {:error, :missing} =
               IdentityStore.read_username(store, index["normalizedUsername"])

      assert :open = Bootstrap.status(store)
    end

    test "refuses to alter a changed pending file", %{store: store} do
      account = valid_account()
      index = valid_index(account)
      journal = pending_journal(account, index)
      changed = %{account | "displayUsername" => "Test-User-Changed"}

      assert {:ok, ^journal} = IdentityStore.put_bootstrap(store, journal)
      assert {:ok, ^changed} = IdentityStore.put_account(store, changed)
      assert {:error, :changed} = Bootstrap.recover(store)
      assert {:ok, ^changed} = IdentityStore.read_account(store, account["userId"])
      assert {:ok, ^journal} = IdentityStore.read_bootstrap(store)
    end

    test "a closed marker never reopens when an account disappears", %{store: store} do
      assert {:ok, [public]} =
               Bootstrap.create(store, [account("test-user-family-admin", password(), ["admin"])])

      {:ok, stored} = IdentityStore.read_account(store, public["userId"])
      assert :ok = IdentityStore.remove_account(store, stored)
      assert :closed = Bootstrap.status(store)
      assert :ok = Bootstrap.recover(store)
      assert :closed = Bootstrap.status(store)
    end
  end

  describe "persistent independent sessions" do
    test "stores only a digest, persists across store recreation, and revokes one browser", %{
      runtime: runtime,
      store: store
    } do
      user = bootstrap_user(store)
      assert {:ok, token_a} = Sessions.create(store, user["userId"])
      assert {:ok, token_b} = Sessions.create(store, user["userId"])
      refute token_a == token_b

      digest_a = Session.digest(token_a)
      session_path = Path.join(runtime.path, "system/sessions/#{digest_a}.json")
      session_bytes = File.read!(session_path)
      refute session_bytes =~ token_a
      refute session_bytes =~ token_b
      refute session_bytes =~ "expires"

      restarted_store = RecordIdentityStore.new(FileRecordBackend.new!(runtime.path))
      assert {:ok, ^user} = Sessions.current_user(restarted_store, token_a)
      assert {:ok, ^user} = Sessions.current_user(restarted_store, token_b)

      assert {:ok, ^digest_a} = Sessions.revoke(restarted_store, token_a)
      assert {:error, :unauthenticated} = Sessions.current_user(restarted_store, token_a)
      assert {:ok, ^user} = Sessions.current_user(restarted_store, token_b)
      assert {:error, :unauthenticated} = Sessions.current_user(restarted_store, "invalid")
    end
  end

  describe "identity application boundary" do
    test "normalizes malformed login and already-logged-out browser results" do
      assert {:error, :invalid_credentials} = Identity.login(nil, "Synthetic Password 123!")
      assert :ok = Identity.logout("not-a-live-session-token")
    end

    test "refuses to initialize over an unreadable bootstrap journal", %{
      records: records,
      store: store
    } do
      assert {:ok, path} = FileRecordBackend.resolve(records, :bootstrap, nil)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "{not-json")

      assert {:stop, {:identity_recovery_failed, :invalid_state}} =
               Identity.init(store: store)
    end

    # The endpoint notifier must broadcast exactly what the endpoint broadcast before it
    # became an adapter: a `"disconnect"` with an empty payload on `"identity:<digest>"`.
    test "logout disconnects the session's live connections through the endpoint" do
      {username, password} = BnestAppWeb.ConnCase.test_credentials()
      {:ok, token} = Identity.login(username, password)
      topic = "identity:" <> Identity.session_digest(token)
      :ok = Phoenix.PubSub.subscribe(BnestApp.PubSub, topic)

      assert :ok = Identity.logout(token)

      assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "disconnect", payload: %{}}
      assert {:error, :unauthenticated} = Identity.current_user(token)
    end
  end

  describe "authorization" do
    test "unions valid roles only for self-owned capabilities and denies everything else" do
      capabilities =
        ~w(use_chat use_sifat_allah read_theme write_theme confirm_import view_import_status)a

      for roles <- [["children"], ["parents"], ["admin"], ["children", "parents", "admin"]],
          capability <- capabilities do
        user = %{"userId" => "user-owner", "roles" => roles}
        assert Authorization.allow?(user, capability, "user-owner")
        refute Authorization.allow?(user, capability, "user-other")
      end

      user = %{"userId" => "user-owner", "roles" => ["admin"]}
      refute Authorization.allow?(user, :bootstrap_accounts, nil)
      refute Authorization.allow?(user, :manage_accounts, "user-owner")
      refute Authorization.allow?(user, :share_data, "user-other")

      refute Authorization.allow?(
               %{"userId" => "user-owner", "roles" => ["owner"]},
               :use_chat,
               "user-owner"
             )
    end
  end

  defp bootstrap_user(store) do
    {:ok, [user]} =
      Bootstrap.create(store, [account("test-user-family-admin", password(), ["admin"])])

    user
  end

  defp account(username, password, roles),
    do: %{"username" => username, "password" => password, "roles" => roles}

  defp password, do: "Synthetic Password 123!"

  defp valid_account do
    {:ok, verifier} = Argon2CredentialHasher.hash(password())

    %{
      "schemaVersion" => 1,
      "recordType" => "account",
      "userId" => "user-test-user-pending",
      "displayUsername" => "Test-User-Pending-Admin",
      "normalizedUsername" => "test-user-pending-admin",
      "roles" => ["admin"],
      "passwordVerifier" => verifier,
      "createdAt" => timestamp()
    }
  end

  defp valid_index(account) do
    %{
      "schemaVersion" => 1,
      "recordType" => "username-index",
      "normalizedUsername" => account["normalizedUsername"],
      "userId" => account["userId"]
    }
  end

  defp pending_journal(account, index) do
    %{
      "schemaVersion" => 1,
      "recordType" => "bootstrap",
      "state" => "pending",
      "attemptId" => "bootstrap-pending-test",
      "startedAt" => timestamp(),
      "closedAt" => nil,
      "accounts" => [
        %{
          "userId" => account["userId"],
          "normalizedUsername" => account["normalizedUsername"],
          "accountSha256" => digest(account),
          "indexSha256" => digest(index)
        }
      ]
    }
  end

  defp digest(record),
    do: :crypto.hash(:sha256, Jason.encode!(record)) |> Base.encode16(case: :lower)

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
