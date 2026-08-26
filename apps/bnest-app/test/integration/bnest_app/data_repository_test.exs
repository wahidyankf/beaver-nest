defmodule BnestApp.DataRepositoryTest do
  use ExUnit.Case, async: false

  alias BnestApp.DataRepository
  alias BnestApp.DataRepository.Schema
  alias BnestApp.DataRepository.Store
  alias BnestApp.TestIdentity
  alias BnestApp.TestRuntimeRoot

  describe "isolated test runtime roots" do
    test "creates a marked mirrored root and removes only that root" do
      runtime = TestRuntimeRoot.create!("repository")
      cleanup_on_exit(runtime)
      run_id = runtime.run_id

      assert String.starts_with?(runtime.run_id, "repository-")
      assert File.dir?(Path.join(runtime.path, "general"))
      assert File.dir?(Path.join(runtime.path, "apps/beaver-nest"))
      assert File.dir?(Path.join(runtime.path, "system"))
      assert File.dir?(Path.join(runtime.path, "users"))

      assert %{
               "schemaVersion" => 1,
               "recordType" => "bnest-test-run",
               "runId" => ^run_id,
               "owner" => "bnest-test-harness"
             } = Jason.decode!(File.read!(Path.join(runtime.path, ".bnest-test-run.json")))

      assert :ok = TestRuntimeRoot.cleanup!(runtime)
      refute File.exists?(runtime.path)
      assert File.dir?(TestRuntimeRoot.runs_root())
    end

    test "rejects production, the shared runs root, and symlinks before mutation" do
      assert {:error, :production_root} =
               TestRuntimeRoot.validate(TestRuntimeRoot.production_root())

      assert {:error, :shared_root} = TestRuntimeRoot.validate(TestRuntimeRoot.runs_root())

      runtime = TestRuntimeRoot.create!("symlink-target")
      cleanup_on_exit(runtime)
      link = Path.join(TestRuntimeRoot.runs_root(), "symlink-runtime")
      File.ln_s!(runtime.path, link)

      assert {:error, :symlink} = TestRuntimeRoot.validate(link)

      File.rm!(link)
      assert :ok = TestRuntimeRoot.cleanup!(runtime)
    end

    test "cleanup refuses a live registered process" do
      runtime = TestRuntimeRoot.create!("live-process")
      cleanup_on_exit(runtime)
      pid = spawn(fn -> Process.sleep(:infinity) end)

      assert {:error, :processes_running} = TestRuntimeRoot.cleanup(runtime, [pid])
      assert File.dir?(runtime.path)

      Process.exit(pid, :kill)
      refute Process.alive?(pid)
      assert :ok = TestRuntimeRoot.cleanup!(runtime)
    end
  end

  describe "synthetic identities" do
    test "derives a test-user identity inside the same marked run" do
      runtime = TestRuntimeRoot.create!("identity")
      cleanup_on_exit(runtime)
      identity = TestIdentity.create!(runtime, "authentication")

      assert String.starts_with?(identity.username, "test-user-")
      assert String.length(identity.username) <= 32
      assert String.length(identity.password) >= 15
      assert identity.runtime_root == runtime.path
      assert identity.account_index_root == Path.join(runtime.path, "system/usernames")
      assert identity.family_list_root == Path.join(runtime.path, "system/accounts")

      assert :ok = TestRuntimeRoot.cleanup!(runtime)
    end
  end

  describe "versioned data contracts" do
    test "accepts every version-one record family" do
      Enum.each(valid_records(), fn record ->
        assert {:ok, ^record} = Schema.validate(record)
      end)
    end

    test "rejects unsupported versions, missing fields, and sensitive extras" do
      account = valid_account()

      assert {:error, :unsupported_version} =
               account |> Map.put("schemaVersion", 2) |> Schema.validate()

      assert {:error, :invalid_schema} = account |> Map.delete("roles") |> Schema.validate()

      assert {:error, :invalid_schema} =
               account |> Map.put("plaintextPassword", "never-store-this") |> Schema.validate()
    end

    test "rejects invalid IDs, source combinations, checksums, and source limits" do
      account = valid_account()

      assert {:error, :invalid_schema} =
               account |> Map.put("userId", "../other") |> Schema.validate()

      envelope = valid_browser_import()

      assert {:error, :unsupported_source} =
               envelope
               |> put_in(["source", "storageKey"], "unknown.key")
               |> Schema.validate()

      assert {:error, :checksum_mismatch} =
               envelope
               |> put_in(["integrity", "sha256"], String.duplicate("0", 64))
               |> Schema.validate()

      assert {:error, :oversized} =
               envelope
               |> Map.put("payload", String.duplicate("x", 500_001))
               |> Schema.validate()
    end

    test "projects only public structure and never record values" do
      projection = Schema.structural_projection(valid_account())

      assert projection["recordType"] == "account"
      assert projection["schemaVersion"] == 1
      assert projection["fields"]["passwordVerifier"] == "string"
      refute inspect(projection) =~ "test-user"
      refute inspect(projection) =~ "$argon2id$"
      refute inspect(projection) =~ "user-test"
    end
  end

  describe "typed atomic store" do
    setup do
      runtime = TestRuntimeRoot.create!("store")
      cleanup_on_exit(runtime)
      %{runtime: runtime, store: Store.new!(runtime.path)}
    end

    test "derives paths only from typed server IDs and rejects traversal", %{store: store} do
      assert {:ok, path} = Store.resolve(store, :chat, "user-test-admin")
      assert String.ends_with?(path, "users/user-test-admin/chat/current.json")
      assert {:error, :invalid_id} = Store.resolve(store, :chat, "../other-user")

      assert {:error, :unsupported_record_type} =
               Store.resolve(store, :unknown, "user-test-admin")
    end

    test "atomically writes, re-reads, and rejects a stale same-revision race", %{store: store} do
      initial = valid_chat()

      assert {:ok, %{"revision" => 0}} =
               Store.write(store, :chat, initial["ownerId"], nil, initial)

      candidate_a = put_in(initial, ["state", "model"], "model-a")
      candidate_b = put_in(initial, ["state", "model"], "model-b")

      results =
        [candidate_a, candidate_b]
        |> Task.async_stream(
          fn candidate -> Store.write(store, :chat, initial["ownerId"], 0, candidate) end,
          ordered: false,
          max_concurrency: 2
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, %{"revision" => 1}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :stale})) == 1
      assert {:ok, %{"revision" => 1}} = Store.read(store, :chat, initial["ownerId"])
    end

    test "invalid or failed candidates leave the accepted file unchanged", %{runtime: runtime} do
      store = Store.new!(runtime.path)
      initial = valid_theme()
      assert {:ok, ^initial} = Store.write(store, :theme, initial["ownerId"], nil, initial)

      assert {:error, :invalid_schema} =
               Store.write(
                 store,
                 :theme,
                 initial["ownerId"],
                 0,
                 Map.put(initial, "theme", "purple")
               )

      failing_store =
        Store.new!(runtime.path, replace: fn _temporary, _destination -> {:error, :injected} end)

      candidate = Map.put(initial, "theme", "light")

      assert {:error, :atomic_replace_failed} =
               Store.write(failing_store, :theme, initial["ownerId"], 0, candidate)

      assert {:ok, ^initial} = Store.read(store, :theme, initial["ownerId"])
    end

    test "creates, replaces, and removes exact identity records without revisions", %{
      store: store
    } do
      account = valid_account()

      assert {:ok, ^account} = Store.put_new(store, :account, account["userId"], account)
      assert {:error, :exists} = Store.put_new(store, :account, account["userId"], account)

      changed = %{account | "displayUsername" => "test-user-admin-2"}
      assert {:ok, ^changed} = Store.replace(store, :account, account["userId"], changed)
      assert {:error, :changed} = Store.remove_exact(store, :account, account["userId"], account)
      assert :ok = Store.remove_exact(store, :account, account["userId"], changed)
      assert {:error, :missing} = Store.read(store, :account, account["userId"])
    end
  end

  describe "application repository facade" do
    test "creates, replaces, reads, and removes an exact server-owned record" do
      user_id = "user-facade-test"

      account = %{
        "schemaVersion" => 1,
        "recordType" => "account",
        "userId" => user_id,
        "displayUsername" => "test-user-facade",
        "normalizedUsername" => "test-user-facade",
        "roles" => ["admin"],
        "passwordVerifier" => "$argon2id$synthetic-test-verifier",
        "createdAt" => timestamp()
      }

      assert {:ok, ^account} = DataRepository.put_new(:account, user_id, account)
      assert {:ok, ^account} = DataRepository.read(:account, user_id)

      changed = %{account | "displayUsername" => "test-user-facade-2"}
      assert {:ok, ^changed} = DataRepository.replace(:account, user_id, changed)
      assert :ok = DataRepository.remove_exact(:account, user_id, changed)
      assert {:error, :missing} = DataRepository.read(:account, user_id)
    end
  end

  defp cleanup_on_exit(runtime) do
    on_exit(fn ->
      if File.exists?(runtime.path), do: TestRuntimeRoot.cleanup!(runtime)
    end)
  end

  defp valid_records do
    [
      valid_bootstrap(),
      valid_account(),
      valid_username_index(),
      valid_session(),
      valid_browser_import(),
      valid_chat(),
      valid_sifat_allah(),
      valid_theme(),
      valid_manifest(),
      valid_registry(),
      valid_marker()
    ]
  end

  defp valid_bootstrap do
    %{
      "schemaVersion" => 1,
      "recordType" => "bootstrap",
      "state" => "closed",
      "attemptId" => "bootstrap-test-001",
      "startedAt" => timestamp(),
      "closedAt" => timestamp(),
      "accounts" => [
        %{
          "userId" => "user-test-admin",
          "normalizedUsername" => "test-user-admin",
          "accountSha256" => digest("account"),
          "indexSha256" => digest("index")
        }
      ]
    }
  end

  defp valid_account do
    %{
      "schemaVersion" => 1,
      "recordType" => "account",
      "userId" => "user-test-admin",
      "displayUsername" => "test-user-admin",
      "normalizedUsername" => "test-user-admin",
      "roles" => ["parents", "admin"],
      "passwordVerifier" => "$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA",
      "createdAt" => timestamp()
    }
  end

  defp valid_username_index do
    %{
      "schemaVersion" => 1,
      "recordType" => "username-index",
      "normalizedUsername" => "test-user-admin",
      "userId" => "user-test-admin"
    }
  end

  defp valid_session do
    %{
      "schemaVersion" => 1,
      "recordType" => "browser-session",
      "tokenDigest" => digest("session"),
      "userId" => "user-test-admin",
      "issuedAt" => timestamp(),
      "revokedAt" => nil
    }
  end

  defp valid_browser_import do
    payload = Jason.encode!(%{"version" => 2, "messages" => []})

    %{
      "schemaVersion" => 1,
      "recordType" => "browser-import",
      "importId" => "import-test-001",
      "ownerId" => "user-test-admin",
      "source" => %{
        "kind" => "browser-storage",
        "storageArea" => "sessionStorage",
        "storageKey" => "bnest.chat.v1",
        "sourceSchemaVersion" => 2
      },
      "payloadEncoding" => "utf8-string",
      "payload" => payload,
      "integrity" => %{"sha256" => digest(payload), "capturedAt" => timestamp()}
    }
  end

  defp valid_chat do
    %{
      "schemaVersion" => 1,
      "recordType" => "chat",
      "ownerId" => "user-test-admin",
      "sourceImportId" => nil,
      "revision" => 0,
      "state" => %{
        "version" => 2,
        "thread_id" => nil,
        "model" => "gpt-test",
        "reasoning_effort" => "medium",
        "messages" => []
      },
      "updatedAt" => timestamp()
    }
  end

  defp valid_sifat_allah do
    %{
      "schemaVersion" => 1,
      "recordType" => "sifat-allah-progress",
      "ownerId" => "user-test-admin",
      "sourceImportId" => nil,
      "revision" => 0,
      "progress" => %{
        "version" => 2,
        "learned_ids" => [],
        "review_ids" => [],
        "mastered_key_ids" => [],
        "review_key_ids" => [],
        "correct_answers" => 0,
        "incorrect_answers" => 0
      },
      "session" => %{"mode" => "dashboard"},
      "updatedAt" => timestamp()
    }
  end

  defp valid_theme do
    %{
      "schemaVersion" => 1,
      "recordType" => "theme-preference",
      "ownerId" => "user-test-admin",
      "sourceImportId" => nil,
      "revision" => 0,
      "theme" => "dark",
      "updatedAt" => timestamp()
    }
  end

  defp valid_manifest do
    %{
      "schemaVersion" => 1,
      "recordType" => "import-manifest",
      "importId" => "import-test-001",
      "ownerId" => "user-test-admin",
      "source" => %{
        "kind" => "browser-storage",
        "reference" => "bnest.chat.v1",
        "sha256" => digest("source")
      },
      "destination" => %{
        "recordType" => "chat",
        "relativePathTemplate" => "users/<owner-id>/chat/current.json"
      },
      "recoverySource" => %{
        "kind" => "import-envelope",
        "relativePathTemplate" => "users/<owner-id>/imports/<import-id>.json#payload",
        "sha256" => digest("source")
      },
      "status" => "accepted",
      "attempt" => 1,
      "startedAt" => timestamp(),
      "completedAt" => timestamp(),
      "failureCategory" => nil
    }
  end

  defp valid_registry do
    %{
      "schemaVersion" => 1,
      "recordType" => "schema-registry",
      "supported" => %{"chat" => [1], "account" => [1]},
      "migrations" => [
        %{
          "recordType" => "chat-source",
          "from" => 1,
          "to" => 2,
          "migrationId" => "chat-source-v1-to-v2"
        }
      ]
    }
  end

  defp valid_marker do
    %{
      "schemaVersion" => 1,
      "recordType" => "bnest-test-run",
      "runId" => "run-test-001",
      "createdAt" => timestamp(),
      "owner" => "bnest-test-harness"
    }
  end

  defp timestamp, do: "2030-01-01T00:00:00Z"
  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
