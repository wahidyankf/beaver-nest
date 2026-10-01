defmodule BnestApp.Storage.Domain.FlatMigrationTest do
  use ExUnit.Case, async: true

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.FlatMigration

  @owner "user-test-flat"
  @theme %{
    "schemaVersion" => 1,
    "recordType" => "theme-preference",
    "ownerId" => @owner,
    "sourceImportId" => nil,
    "revision" => 0,
    "theme" => "dark",
    "updatedAt" => "2026-10-01T00:00:00Z"
  }
  @theme_path "users/#{@owner}/preferences/theme.json"

  test "classifies records, legacy recovery payloads, and everything else" do
    assert {:ok, {:record, %{type: :theme}}} = FlatMigration.classify_source(@theme_path)

    assert FlatMigration.classify_source("apps/beaver-nest/legacy/import-old/source.bin") ==
             {:ok,
              {:recovery, %{owner_kind: "app", owner_key: "beaver-nest", import_id: "import-old"}}}

    assert FlatMigration.classify_source("users/#{@owner}/legacy/import-old/source.bin") ==
             {:ok, {:recovery, %{owner_kind: "user", owner_key: @owner, import_id: "import-old"}}}

    assert FlatMigration.classify_source("users/-bad-/legacy/import-old/source.bin") ==
             {:error, :unsupported_source}

    assert FlatMigration.classify_source("users/#{@owner}/notes.txt") ==
             {:error, :unsupported_source}
  end

  test "assesses a source record by the schema" do
    bytes = Jason.encode!(@theme)

    assert {:accepted, %{identity: @owner, record: @theme}} =
             FlatMigration.assess_record(@theme_path, bytes, kinds())

    assert {:invalid, %{classification: %{type: :theme}}} =
             FlatMigration.assess_record(@theme_path, "{not json", kinds())

    assert {:unsupported, %{source_sha256: sha}} =
             FlatMigration.assess_record("notes.txt", bytes, kinds())

    assert sha == FlatMigration.sha256(bytes)
  end

  test "a source matches its migrated record until SQLite becomes primary" do
    bytes = Jason.encode!(@theme)
    changed = {:ok, %{@theme | "theme" => "light"}}

    assert FlatMigration.record_matches?(bytes, {:ok, @theme}, :flat_primary, kinds())
    refute FlatMigration.record_matches?(bytes, changed, :flat_primary, kinds())
    assert FlatMigration.record_matches?(bytes, changed, :sqlite_primary, kinds())
    refute FlatMigration.record_matches?(bytes, {:error, :missing}, :sqlite_primary, kinds())
    refute FlatMigration.record_matches?("{not json", {:ok, @theme}, :flat_primary, kinds())
  end

  test "the run fails on any blocked item and verifies only once SQLite is primary" do
    assert FlatMigration.run_state(1, :sqlite_primary) == "failed"
    assert FlatMigration.run_state(0, :sqlite_primary) == "verified"
    assert FlatMigration.run_state(0, :flat_primary) == "copying"

    assert FlatMigration.outcome_counts([:accepted, :invalid, :changed, :failed, :unsupported]) ==
             %{accepted: 1, blocked: 3, unsupported: 1}
  end

  test "names the identity and item of each classified source" do
    assert FlatMigration.identity_of(%{type: :bootstrap}) == nil
    assert FlatMigration.identity_of(%{type: :schema_registry}) == nil

    assert FlatMigration.identity_of(%{
             type: :browser_import,
             owner_id: @owner,
             record_key: "#{@owner}:import-a"
           }) == {@owner, "import-a"}

    assert FlatMigration.identity_of(%{type: :chat, record_key: @owner}) == @owner

    assert FlatMigration.item_classification({:record, %{record_type: "chat"}}) ==
             %{record_type: "chat"}

    assert FlatMigration.item_classification(
             {:recovery, %{owner_kind: "user", owner_key: @owner, import_id: "import-a"}}
           ) == %{record_type: "recovery-source", record_key: "user:#{@owner}:import-a"}

    assert FlatMigration.migration_id() == "flat-files-v1-to-sqlite-v1"
    assert FlatMigration.order_inventory(["b", "a"]) == ["a", "b"]
  end

  defp kinds, do: Storage.record_kinds()
end
