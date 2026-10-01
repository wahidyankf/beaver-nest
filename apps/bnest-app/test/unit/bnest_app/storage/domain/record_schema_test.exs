defmodule BnestApp.Storage.Domain.RecordSchemaTest do
  # Characterization: pins which schema versions every record kind accepts, so moving the
  # schema into the Storage domain cannot change what the repository reads or writes.
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.SifatAllah.Domain.Quiz
  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.RecordSchema

  @timestamp "2026-10-01T00:00:00Z"
  @sha String.duplicate("a", 64)

  defp samples do
    {:ok, chat_state} = Transcript.snapshot(Transcript.new())

    [
      %{
        "recordType" => "bootstrap",
        "state" => "pending",
        "attemptId" => "attempt-characterization",
        "startedAt" => @timestamp,
        "closedAt" => nil,
        "accounts" => [
          %{
            "userId" => "user-test-characterization",
            "normalizedUsername" => "test-user-characterization",
            "accountSha256" => @sha,
            "indexSha256" => @sha
          }
        ]
      },
      %{
        "recordType" => "account",
        "userId" => "user-test-characterization",
        "displayUsername" => "test-user-characterization",
        "normalizedUsername" => "test-user-characterization",
        "roles" => ["parents"],
        "passwordVerifier" => "$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA",
        "createdAt" => @timestamp
      },
      %{
        "recordType" => "username-index",
        "normalizedUsername" => "test-user-characterization",
        "userId" => "user-test-characterization"
      },
      %{
        "recordType" => "browser-session",
        "tokenDigest" => @sha,
        "userId" => "user-test-characterization",
        "issuedAt" => @timestamp,
        "revokedAt" => nil
      },
      %{
        "recordType" => "browser-import",
        "importId" => "import-characterization",
        "ownerId" => "user-test-characterization",
        "source" => %{
          "kind" => "browser-storage",
          "storageArea" => "localStorage",
          "storageKey" => "phx:theme",
          "sourceSchemaVersion" => 1
        },
        "payloadEncoding" => "utf8-string",
        "payload" => "dark",
        "integrity" => %{
          "sha256" => :crypto.hash(:sha256, "dark") |> Base.encode16(case: :lower),
          "capturedAt" => @timestamp
        }
      },
      %{
        "recordType" => "chat",
        "ownerId" => "user-test-characterization",
        "sourceImportId" => nil,
        "revision" => 0,
        "state" => chat_state,
        "updatedAt" => @timestamp
      },
      %{
        "recordType" => "sifat-allah-progress",
        "ownerId" => "user-test-characterization",
        "sourceImportId" => nil,
        "revision" => 0,
        "progress" => Quiz.progress(),
        "session" => nil,
        "updatedAt" => @timestamp
      },
      %{
        "recordType" => "theme-preference",
        "ownerId" => "user-test-characterization",
        "sourceImportId" => nil,
        "revision" => 0,
        "theme" => "dark",
        "updatedAt" => @timestamp
      },
      %{
        "recordType" => "import-manifest",
        "importId" => "import-characterization",
        "ownerId" => "user-test-characterization",
        "source" => %{"kind" => "browser-storage", "reference" => "phx:theme", "sha256" => @sha},
        "destination" => %{
          "recordType" => "theme-preference",
          "relativePathTemplate" => "users/<owner-id>/preferences/theme.json"
        },
        "recoverySource" => %{
          "kind" => "import-envelope",
          "relativePathTemplate" => "users/<owner-id>/imports/<import-id>.json#payload",
          "sha256" => @sha
        },
        "status" => "pending",
        "attempt" => 1,
        "startedAt" => @timestamp,
        "completedAt" => nil,
        "failureCategory" => nil
      },
      %{
        "recordType" => "schema-registry",
        "supported" => %{"chat" => [1]},
        "migrations" => []
      },
      %{
        "recordType" => "bnest-test-run",
        "runId" => "run-characterization",
        "createdAt" => @timestamp,
        "owner" => "bnest-test-harness"
      }
    ]
    |> Enum.map(&Map.put(&1, "schemaVersion", 1))
  end

  defp validate(record), do: RecordSchema.validate(record, Storage.record_kinds())

  test "every record kind accepts schema version 1" do
    for record <- samples() do
      assert validate(record) == {:ok, record}, record["recordType"]
    end
  end

  test "every record kind rejects any other schema version" do
    for record <- samples(), version <- [0, 2, "1"] do
      assert validate(%{record | "schemaVersion" => version}) == {:error, :unsupported_version},
             "#{record["recordType"]} v#{inspect(version)}"
    end
  end

  test "a record without a schema version is invalid" do
    for record <- samples() do
      assert validate(Map.delete(record, "schemaVersion")) == {:error, :invalid_schema},
             record["recordType"]
    end
  end

  test "an unknown record type is invalid" do
    assert validate(%{"schemaVersion" => 1, "recordType" => "unknown"}) ==
             {:error, :invalid_schema}
  end

  test "every record kind rejects an unexpected field" do
    for record <- samples() do
      assert validate(Map.put(record, "unexpected", true)) == {:error, :invalid_schema},
             record["recordType"]
    end
  end

  test "a kind-owned record type is invalid when no kind registers it" do
    chat = Enum.find(samples(), &(&1["recordType"] == "chat"))

    assert RecordSchema.validate(chat, []) == {:error, :invalid_schema}
    assert validate(%{chat | "ownerId" => "not an id"}) == {:error, :invalid_schema}
  end

  test "a closed bootstrap needs its closing time" do
    bootstrap = sample("bootstrap")
    closed = %{bootstrap | "state" => "closed", "closedAt" => @timestamp}

    assert validate(closed) == {:ok, closed}
    assert validate(%{closed | "closedAt" => nil}) == {:error, :invalid_schema}
    assert validate(%{bootstrap | "closedAt" => @timestamp}) == {:error, :invalid_schema}
    assert validate(%{bootstrap | "startedAt" => 1}) == {:error, :invalid_schema}

    assert validate(%{bootstrap | "accounts" => [%{"userId" => "user-test-characterization"}]}) ==
             {:error, :invalid_schema}
  end

  test "a revoked session carries a revocation time" do
    session = sample("browser-session")
    revoked = %{session | "revokedAt" => @timestamp}

    assert validate(revoked) == {:ok, revoked}
    assert validate(%{session | "revokedAt" => "yesterday"}) == {:error, :invalid_schema}
  end

  test "a test-run marker may name its process and host" do
    marker = sample("bnest-test-run") |> Map.merge(%{"pid" => "123", "hostname" => "host"})

    assert validate(marker) == {:ok, marker}
    assert validate(%{marker | "pid" => 123}) == {:error, :invalid_schema}
  end

  test "a browser import must come from an allowed, bounded, intact source" do
    envelope = sample("browser-import")

    unsupported = put_in(envelope, ["source", "storageKey"], "unknown")
    assert validate(unsupported) == {:error, :unsupported_source}

    for {area, key, limit} <- [
          {"sessionStorage", "bnest.chat.v1", 500_000},
          {"localStorage", "bnest.sifat-allah.v1", 10_000}
        ] do
      payload = String.duplicate("x", limit + 1)

      oversized =
        envelope
        |> Map.put("payload", payload)
        |> put_in(["source", "storageArea"], area)
        |> put_in(["source", "storageKey"], key)

      assert validate(oversized) == {:error, :oversized}
    end

    assert validate(%{envelope | "payload" => "light"}) == {:error, :checksum_mismatch}
    assert validate(%{envelope | "payloadEncoding" => "base64"}) == {:error, :invalid_schema}
  end

  test "a manifest checks its destination and recovery source" do
    manifest = sample("import-manifest")

    assert validate(%{manifest | "destination" => %{"recordType" => "chat"}}) ==
             {:error, :invalid_schema}

    assert validate(%{manifest | "failureCategory" => "malformed", "status" => "rejected"}) ==
             {:ok, %{manifest | "failureCategory" => "malformed", "status" => "rejected"}}

    assert validate(%{manifest | "failureCategory" => "unknown"}) == {:error, :invalid_schema}
  end

  test "a schema registry lists only forward migrations" do
    registry = sample("schema-registry")

    migration = %{
      "recordType" => "chat",
      "from" => 1,
      "to" => 2,
      "migrationId" => "chat-v1-to-v2"
    }

    with_migration = %{registry | "migrations" => [migration]}
    assert validate(with_migration) == {:ok, with_migration}

    assert validate(%{registry | "migrations" => [%{migration | "to" => 1}]}) ==
             {:error, :invalid_schema}

    assert validate(%{registry | "migrations" => [Map.delete(migration, "to")]}) ==
             {:error, :invalid_schema}
  end

  test "a structural projection names each field's JSON type" do
    record = %{
      "schemaVersion" => 1,
      "recordType" => "probe",
      "nothing" => nil,
      "text" => "a",
      "count" => 1,
      "ratio" => 1.5,
      "flag" => true,
      "items" => [],
      "nested" => %{}
    }

    assert RecordSchema.structural_projection(record) == %{
             "recordType" => "probe",
             "schemaVersion" => 1,
             "fields" => %{
               "schemaVersion" => "integer",
               "recordType" => "string",
               "nothing" => "null",
               "text" => "string",
               "count" => "integer",
               "ratio" => "number",
               "flag" => "boolean",
               "items" => "array",
               "nested" => "object"
             }
           }
  end

  test "exact? only accepts maps" do
    refute RecordSchema.exact?(["schemaVersion"], ["schemaVersion"])
  end

  defp sample(type), do: Enum.find(samples(), &(&1["recordType"] == type))
end
