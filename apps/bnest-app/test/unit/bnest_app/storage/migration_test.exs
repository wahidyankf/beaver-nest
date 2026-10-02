defmodule BnestApp.Storage.MigrationTest do
  # Not async: the doubles replace the application-wide Storage configuration.
  use ExUnit.Case, async: false

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.CanonicalJson
  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Storage.Migration
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.StoragePorts.{DatabaseLifecycle, FlatSource, MigrationLedger}

  @flat_root "/in-memory/flat"
  @z_theme "users/z-test-user/preferences/theme.json"
  @a_theme "users/a-test-user/preferences/theme.json"
  @recovery "users/a-test-user/legacy/import-1/source.bin"

  setup do
    previous = StoragePorts.install()
    on_exit(fn -> StoragePorts.restore(previous) end)
    :ok
  end

  describe "inventory" do
    test "keeps only supported sources, in path order" do
      FlatSource.put_files(@flat_root, [
        {@z_theme, theme("z-test-user", "dark")},
        {"notes/readme.txt", "ignored"},
        {@a_theme, theme("a-test-user", "light")}
      ])

      assert Migration.inventory(@flat_root) == [@a_theme, @z_theme]
    end
  end

  describe "a run" do
    test "copies each valid record and recovery source with checksum evidence" do
      FlatSource.put_files(@flat_root, [
        {@z_theme, theme("z-test-user", "dark")},
        {@recovery, "legacy bytes"},
        {@a_theme, theme("a-test-user", "light")}
      ])

      assert %{migration_id: "flat-files-v1-to-sqlite-v1", accepted: 3, blocked: 0} =
               result = Migration.run(@flat_root)

      assert result.unsupported == 0
      assert result.state == "copying"

      ledger = MigrationLedger.state()
      assert [%{state: "copying", ddl_checksum: checksum, source_fingerprint: fp}] = ledger.runs

      assert checksum ==
               :sha256
               |> :crypto.hash(Enum.join(DatabaseLifecycle.schema_sources()))
               |> Base.encode16(case: :lower)

      assert fp == expected_fingerprint([@recovery, @a_theme, @z_theme])

      theme_item = ledger.items[{"flat-files-v1-to-sqlite-v1", @a_theme}]
      assert theme_item.outcome == "accepted"
      assert theme_item.source_sha256 == sha(theme("a-test-user", "light"))

      assert theme_item.target_sha256 ==
               CanonicalJson.sha256(Jason.decode!(theme("a-test-user", "light")))

      recovery_item = ledger.items[{"flat-files-v1-to-sqlite-v1", @recovery}]
      assert recovery_item.record_type == "recovery-source"
      assert recovery_item.target_sha256 == sha("legacy bytes")

      {_backend, sqlite} = Storage.record_backend()

      assert InMemoryRecordBackend.read(sqlite, :theme, "a-test-user") ==
               {:ok, Jason.decode!(theme("a-test-user", "light"))}

      assert Migration.parity_ok?(@flat_root)
      refute Migration.blocked?()
    end

    test "reuses accepted items on retry and records a changed source" do
      FlatSource.put_files(@flat_root, [{@a_theme, theme("a-test-user", "light")}])
      Migration.run(@flat_root)
      copies = copy_writes()

      assert %{accepted: 1, blocked: 0} = Migration.run(@flat_root)
      assert copy_writes() == copies
      assert length(MigrationLedger.state().runs) == 1

      FlatSource.put_files(@flat_root, [{@a_theme, theme("a-test-user", "dark")}])
      assert %{accepted: 0, blocked: 1, state: "failed"} = Migration.run(@flat_root)

      assert %{outcome: "changed", error_category: "changed_source", target_sha256: nil} =
               MigrationLedger.state().items[{"flat-files-v1-to-sqlite-v1", @a_theme}]

      assert Migration.blocked?()
      refute Migration.parity_ok?(@flat_root)
    end

    test "blocks a malformed record and a colliding recovery source" do
      FlatSource.put_files(@flat_root, [{@a_theme, "{malformed"}, {@recovery, "first"}])
      MigrationLedger.put_recovery_source!(recovery_row("other bytes"))

      assert %{accepted: 0, blocked: 2, state: "failed"} = Migration.run(@flat_root)
      items = MigrationLedger.state().items

      assert items[{"flat-files-v1-to-sqlite-v1", @a_theme}].error_category == "malformed"

      assert items[{"flat-files-v1-to-sqlite-v1", @recovery}].error_category ==
               "recovery_collision"
    end

    test "a run under SQLite authority is verified" do
      StoragePorts.put(:config, %{"phase" => "sqlite_primary"})
      FlatSource.put_files(@flat_root, [{@a_theme, theme("a-test-user", "light")}])

      assert %{state: "verified"} = Migration.run(@flat_root)
    end
  end

  describe "activation" do
    test "switches storage authority and marks the run verified" do
      StoragePorts.put(:config, %{"phase" => "flat_primary"})
      FlatSource.put_files(@flat_root, [{@a_theme, theme("a-test-user", "light")}])
      Migration.run(@flat_root)

      assert :ok = Migration.activate!()
      assert Storage.phase() == :sqlite_primary
      assert [%{state: "verified", verified_at: verified_at}] = MigrationLedger.state().runs
      assert is_binary(verified_at)
    end
  end

  defp theme(owner, value),
    do:
      Jason.encode!(%{
        "schemaVersion" => 1,
        "recordType" => "theme-preference",
        "ownerId" => owner,
        "sourceImportId" => nil,
        "revision" => 1,
        "theme" => value,
        "updatedAt" => "2026-09-01T00:00:00Z"
      })

  defp recovery_row(bytes),
    do: %{
      owner_kind: "user",
      owner_key: "a-test-user",
      import_id: "import-1",
      payload_blob: bytes,
      payload_sha256: sha(bytes),
      byte_size: byte_size(bytes),
      inserted_at: "2026-09-01T00:00:00Z"
    }

  defp expected_fingerprint(paths) do
    files = Map.new(FlatSource.files(@flat_root))

    paths
    |> Enum.map_join("\n", &(&1 <> ":" <> sha(Map.fetch!(files, &1))))
    |> sha()
  end

  defp copy_writes,
    do:
      Enum.filter(
        MigrationLedger.state().writes,
        &(elem(&1, 0) in [:put_record, :put_item, :put_recovery_source])
      )

  defp sha(bytes), do: FlatMigration.sha256(bytes)
end
