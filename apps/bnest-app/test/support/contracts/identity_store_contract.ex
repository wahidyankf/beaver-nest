defmodule BnestApp.Test.Contracts.IdentityStoreContract do
  @moduledoc """
  The behaviour every `BnestApp.Identity.Ports.IdentityStore` implementation shares. A test
  module uses this template and defines `new_store/1`, which takes the ExUnit context and
  returns a fresh, empty store handle; the template then runs the whole contract against it.

  The records belong to synthetic `test-user-` identities and satisfy the version-1 record
  schema, because the record-backed store validates every record it writes. The password
  verifier is a fixed synthetic string, not the hash of any password.
  """

  use ExUnit.CaseTemplate

  @timestamp "2026-09-01T00:00:00Z"
  @verifier "$argon2id$v=19$m=8,t=1,p=1$dGVzdC11c2VyLXNhbHQ$dGVzdC11c2VyLWhhc2g"

  @doc "A schema-valid account for the synthetic user `name`."
  @spec account(String.t(), String.t() | nil) :: map()
  def account(name, display \\ nil) do
    %{
      "schemaVersion" => 1,
      "recordType" => "account",
      "userId" => "user-" <> name,
      "displayUsername" => display || name,
      "normalizedUsername" => name,
      "roles" => ["admin"],
      "passwordVerifier" => @verifier,
      "createdAt" => @timestamp
    }
  end

  @doc "The username index of `account`."
  @spec index(map()) :: map()
  def index(account) do
    %{
      "schemaVersion" => 1,
      "recordType" => "username-index",
      "normalizedUsername" => account["normalizedUsername"],
      "userId" => account["userId"]
    }
  end

  @doc "A live browser session of `account`, keyed by the digest of `seed`."
  @spec session(map(), String.t()) :: map()
  def session(account, seed) do
    %{
      "schemaVersion" => 1,
      "recordType" => "browser-session",
      "tokenDigest" => :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower),
      "userId" => account["userId"],
      "issuedAt" => @timestamp,
      "revokedAt" => nil
    }
  end

  @doc ~s|A bootstrap journal in `state` ("pending" or "closed") naming `account`.|
  @spec journal(map(), String.t()) :: map()
  def journal(account, state) do
    %{
      "schemaVersion" => 1,
      "recordType" => "bootstrap",
      "state" => state,
      "attemptId" => "bootstrap-test-user-contract",
      "startedAt" => @timestamp,
      "closedAt" => if(state == "closed", do: @timestamp),
      "accounts" => [
        %{
          "userId" => account["userId"],
          "normalizedUsername" => account["normalizedUsername"],
          "accountSha256" => String.duplicate("a", 64),
          "indexSha256" => String.duplicate("b", 64)
        }
      ]
    }
  end

  using do
    quote do
      import BnestApp.Test.Contracts.IdentityStoreContract,
        only: [account: 1, account: 2, index: 1, session: 2, journal: 2]

      alias BnestApp.Identity.Ports.IdentityStore

      setup context, do: [store: new_store(context)]

      describe "IdentityStore contract" do
        test "reads absent records as missing", %{store: store} do
          account = account("test-user-contract-a")

          assert IdentityStore.read_account(store, account["userId"]) == {:error, :missing}

          assert IdentityStore.read_username(store, account["normalizedUsername"]) ==
                   {:error, :missing}

          assert IdentityStore.read_session(store, session(account, "a")["tokenDigest"]) ==
                   {:error, :missing}

          assert IdentityStore.read_bootstrap(store) == {:error, :missing}
        end

        test "put_account stores a new account once", %{store: store} do
          account = account("test-user-contract-a")

          assert IdentityStore.put_account(store, account) == {:ok, account}
          assert IdentityStore.read_account(store, account["userId"]) == {:ok, account}

          assert IdentityStore.put_account(store, account("test-user-contract-a", "Other")) ==
                   {:error, :exists}

          assert IdentityStore.read_account(store, account["userId"]) == {:ok, account}
        end

        test "replace_account changes only an existing account", %{store: store} do
          account = account("test-user-contract-a")
          renamed = account("test-user-contract-a", "Test-User-Contract-A")

          assert IdentityStore.replace_account(store, account) == {:error, :missing}
          {:ok, _stored} = IdentityStore.put_account(store, account)
          assert IdentityStore.replace_account(store, renamed) == {:ok, renamed}
          assert IdentityStore.read_account(store, account["userId"]) == {:ok, renamed}
        end

        test "remove_account removes only the expected account", %{store: store} do
          account = account("test-user-contract-a")
          {:ok, _stored} = IdentityStore.put_account(store, account)

          assert IdentityStore.remove_account(store, account("test-user-contract-a", "Other")) ==
                   {:error, :changed}

          assert IdentityStore.read_account(store, account["userId"]) == {:ok, account}
          assert IdentityStore.remove_account(store, account) == :ok
          assert IdentityStore.read_account(store, account["userId"]) == {:error, :missing}
          assert IdentityStore.remove_account(store, account) == :ok
        end

        test "the username index is stored once and removed exactly", %{store: store} do
          index = index(account("test-user-contract-a"))
          other = index(account("test-user-contract-b"))
          moved = %{index | "userId" => other["userId"]}

          assert IdentityStore.put_username(store, index) == {:ok, index}
          assert IdentityStore.read_username(store, index["normalizedUsername"]) == {:ok, index}
          assert IdentityStore.put_username(store, moved) == {:error, :exists}
          assert IdentityStore.remove_username(store, moved) == {:error, :changed}

          assert IdentityStore.read_username(store, other["normalizedUsername"]) ==
                   {:error, :missing}

          assert IdentityStore.remove_username(store, index) == :ok

          assert IdentityStore.read_username(store, index["normalizedUsername"]) ==
                   {:error, :missing}

          assert IdentityStore.remove_username(store, index) == :ok
        end

        test "sessions are stored once and replaced only when present", %{store: store} do
          account = account("test-user-contract-a")
          session = session(account, "a")
          revoked = %{session | "revokedAt" => "2026-09-02T00:00:00Z"}

          assert IdentityStore.replace_session(store, session) == {:error, :missing}
          assert IdentityStore.put_session(store, session) == {:ok, session}
          assert IdentityStore.put_session(store, revoked) == {:error, :exists}
          assert IdentityStore.read_session(store, session["tokenDigest"]) == {:ok, session}
          assert IdentityStore.replace_session(store, revoked) == {:ok, revoked}
          assert IdentityStore.read_session(store, session["tokenDigest"]) == {:ok, revoked}

          assert IdentityStore.read_session(store, session(account, "b")["tokenDigest"]) ==
                   {:error, :missing}
        end

        test "the bootstrap journal is a singleton", %{store: store} do
          account = account("test-user-contract-a")
          pending = journal(account, "pending")
          closed = journal(account, "closed")

          assert IdentityStore.replace_bootstrap(store, closed) == {:error, :missing}
          assert IdentityStore.put_bootstrap(store, pending) == {:ok, pending}
          assert IdentityStore.put_bootstrap(store, closed) == {:error, :exists}
          assert IdentityStore.read_bootstrap(store) == {:ok, pending}
          assert IdentityStore.remove_bootstrap(store, closed) == {:error, :changed}
          assert IdentityStore.replace_bootstrap(store, closed) == {:ok, closed}
          assert IdentityStore.read_bootstrap(store) == {:ok, closed}
          assert IdentityStore.remove_bootstrap(store, closed) == :ok
          assert IdentityStore.read_bootstrap(store) == {:error, :missing}
          assert IdentityStore.remove_bootstrap(store, closed) == :ok
        end

        test "is empty until an account or a username index exists", %{store: store} do
          account = account("test-user-contract-a")

          assert IdentityStore.empty?(store)
          {:ok, _journal} = IdentityStore.put_bootstrap(store, journal(account, "pending"))
          {:ok, _session} = IdentityStore.put_session(store, session(account, "a"))
          assert IdentityStore.empty?(store)

          {:ok, _index} = IdentityStore.put_username(store, index(account))
          refute IdentityStore.empty?(store)
          :ok = IdentityStore.remove_username(store, index(account))
          assert IdentityStore.empty?(store)

          {:ok, _account} = IdentityStore.put_account(store, account)
          refute IdentityStore.empty?(store)
        end

        test "names one lock per store", %{store: store} = context do
          other = new_store(context)

          assert IdentityStore.lock_key(store) == IdentityStore.lock_key(store)
          refute IdentityStore.lock_key(store) == IdentityStore.lock_key(other)
        end
      end
    end
  end
end
