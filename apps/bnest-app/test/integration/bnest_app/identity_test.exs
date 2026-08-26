defmodule BnestApp.IdentityTest do
  use ExUnit.Case, async: false

  alias BnestApp.DataRepository.Store
  alias BnestApp.Identity
  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.CredentialVerifier
  alias BnestApp.Identity.FileStore
  alias BnestApp.Identity.Session
  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("identity-unit")
    on_exit(fn -> if File.exists?(runtime.path), do: TestRuntimeRoot.cleanup!(runtime) end)
    %{runtime: runtime, store: Store.new!(runtime.path)}
  end

  describe "credentials and usernames" do
    test "normalizes ASCII case and enforces username boundaries" do
      assert {:ok, {"Family.Admin", "family.admin"}} =
               FileStore.normalize_username("  Family.Admin  ")

      assert {:ok, {"a", "a"}} = FileStore.normalize_username("a")
      assert {:ok, {username, username}} = FileStore.normalize_username(String.duplicate("a", 32))
      assert {:error, :invalid_username} = FileStore.normalize_username("")
      assert {:error, :invalid_username} = FileStore.normalize_username(String.duplicate("a", 33))
      assert {:error, :invalid_username} = FileStore.normalize_username("-family")
      assert {:error, :invalid_username} = FileStore.normalize_username("family/")
      assert {:error, :invalid_username} = FileStore.normalize_username("fámily")
    end

    test "accepts exact Unicode password boundaries without trimming or truncating" do
      assert CredentialVerifier.valid_password?(String.duplicate(" ", 15))
      assert CredentialVerifier.valid_password?(String.duplicate("🙂", 128))
      refute CredentialVerifier.valid_password?(String.duplicate("x", 14))
      refute CredentialVerifier.valid_password?(String.duplicate("🙂", 129))

      password = "  Synthetic password with spaces  "
      assert {:ok, verifier} = CredentialVerifier.hash(password)
      assert String.starts_with?(verifier, "$argon2id$")
      assert CredentialVerifier.verify(password, verifier)
      refute CredentialVerifier.verify(String.trim(password), verifier)
    end
  end

  describe "one-time bootstrap" do
    test "creates multiple roles and closes permanently without plaintext", %{
      runtime: runtime,
      store: store
    } do
      password = "Synthetic Password 123!"

      assert {:ok, [account]} =
               Bootstrap.create(store, [account("FamilyAdmin", password, ~w(parents admin))])

      assert account["roles"] == ~w(admin parents)
      assert :closed = Bootstrap.status(store)

      assert {:error, :closed} =
               Bootstrap.create(store, [account("AnotherAdmin", password, ["admin"])])

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
                 account("FamilyAdmin", password(), ["admin"]),
                 account("familyadmin", password(), ["children"])
               ])

      assert :open = Bootstrap.status(store)

      assert {:error, :invalid_roles} =
               Bootstrap.create(store, [account("FamilyAdmin", password(), ["owner"])])

      assert {:error, :admin_required} =
               Bootstrap.create(store, [account("FamilyChild", password(), ["children"])])
    end

    test "rolls back only matching files from a pending crash", %{store: store} do
      account = valid_account()
      index = valid_index(account)
      journal = pending_journal(account, index)

      assert {:ok, ^journal} = FileStore.put_bootstrap(store, journal)
      assert {:ok, ^account} = FileStore.put_account(store, account)
      assert {:ok, ^index} = FileStore.put_username(store, index)

      assert :ok = Bootstrap.recover(store)
      assert {:error, :missing} = FileStore.read_bootstrap(store)
      assert {:error, :missing} = FileStore.read_account(store, account["userId"])
      assert {:error, :missing} = FileStore.read_username(store, index["normalizedUsername"])
      assert :open = Bootstrap.status(store)
    end

    test "refuses to alter a changed pending file", %{store: store} do
      account = valid_account()
      index = valid_index(account)
      journal = pending_journal(account, index)
      changed = %{account | "displayUsername" => "ChangedAdmin"}

      assert {:ok, ^journal} = FileStore.put_bootstrap(store, journal)
      assert {:ok, ^changed} = FileStore.put_account(store, changed)
      assert {:error, :changed} = Bootstrap.recover(store)
      assert {:ok, ^changed} = FileStore.read_account(store, account["userId"])
      assert {:ok, ^journal} = FileStore.read_bootstrap(store)
    end

    test "a closed marker never reopens when an account disappears", %{store: store} do
      assert {:ok, [public]} =
               Bootstrap.create(store, [account("FamilyAdmin", password(), ["admin"])])

      {:ok, stored} = FileStore.read_account(store, public["userId"])
      assert :ok = FileStore.remove_account(store, stored)
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
      assert {:ok, token_a} = Session.create(store, user["userId"])
      assert {:ok, token_b} = Session.create(store, user["userId"])
      refute token_a == token_b

      digest_a = Session.digest(token_a)
      session_path = Path.join(runtime.path, "system/sessions/#{digest_a}.json")
      session_bytes = File.read!(session_path)
      refute session_bytes =~ token_a
      refute session_bytes =~ token_b
      refute session_bytes =~ "expires"

      restarted_store = Store.new!(runtime.path)
      assert {:ok, ^user} = Session.current_user(restarted_store, token_a)
      assert {:ok, ^user} = Session.current_user(restarted_store, token_b)

      assert {:ok, ^digest_a} = Session.revoke(restarted_store, token_a)
      assert {:error, :unauthenticated} = Session.current_user(restarted_store, token_a)
      assert {:ok, ^user} = Session.current_user(restarted_store, token_b)
      assert {:error, :unauthenticated} = Session.current_user(restarted_store, "invalid")
    end
  end

  describe "identity application boundary" do
    test "normalizes malformed login and already-logged-out browser results" do
      assert {:error, :invalid_credentials} = Identity.login(nil, "Synthetic Password 123!")
      assert :ok = Identity.logout("not-a-live-session-token")
    end

    test "refuses to initialize over an unreadable bootstrap journal", %{store: store} do
      assert {:ok, path} = Store.resolve(store, :bootstrap, nil)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "{not-json")

      assert {:stop, {:identity_recovery_failed, :invalid_state}} =
               Identity.init(store: store)
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
    {:ok, [user]} = Bootstrap.create(store, [account("FamilyAdmin", password(), ["admin"])])
    user
  end

  defp account(username, password, roles),
    do: %{"username" => username, "password" => password, "roles" => roles}

  defp password, do: "Synthetic Password 123!"

  defp valid_account do
    {:ok, verifier} = CredentialVerifier.hash(password())

    %{
      "schemaVersion" => 1,
      "recordType" => "account",
      "userId" => "user-pending-test",
      "displayUsername" => "PendingAdmin",
      "normalizedUsername" => "pendingadmin",
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
