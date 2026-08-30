defmodule BnestApp.SqliteStorageTest do
  use ExUnit.Case, async: false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.TestRuntimeRoot

  @expected_tables ~w(
    bnest_records
    bnest_recovery_sources
    bnest_migration_runs
    bnest_migration_items
    bnest_schedules
    bnest_schedule_runs
  )
  @insert_record_sql """
  INSERT INTO bnest_records
    (record_type, record_key, owner_id, schema_version, revision, payload_json, payload_sha256, inserted_at, updated_at)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  """

  setup do
    runtime = TestRuntimeRoot.create!("sqlite-ddl")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")

    :ok = StorageCoordinator.ensure_started!(database_path)
    {:ok, _versions, _apps} = migrate(:up)

    on_exit(fn ->
      StorageCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    :ok
  end

  test "creates every declared table and index exactly once" do
    objects = schema_object_names()

    assert Enum.all?(@expected_tables, &(&1 in objects))
    assert "bnest_records_owner_type" in objects
    assert "bnest_migration_items_outcome" in objects
  end

  test "reapplying the committed migration set is idempotent" do
    before_schema = schema_snapshot()
    before_versions = schema_migration_versions()

    {:ok, _versions, _apps} = migrate(:up)

    after_schema = schema_snapshot()
    after_versions = schema_migration_versions()

    assert before_schema != []
    assert before_schema == after_schema
    assert before_versions == after_versions
    assert length(after_versions) == 2
  end

  test "accepts a well-formed record and returns it unchanged" do
    checksum = String.duplicate("a", 64)

    assert {:ok, _result} =
             insert_record(record_key: "user-ddl-roundtrip", payload_sha256: checksum)

    %{rows: [[payload_json, payload_sha256]]} =
      SqliteRepo.query!(
        "SELECT payload_json, payload_sha256 FROM bnest_records WHERE record_key = ?",
        [
          "user-ddl-roundtrip"
        ]
      )

    assert payload_json == "{}"
    assert payload_sha256 == checksum
  end

  test "rejects records with malformed JSON payloads" do
    assert {:error, %Exqlite.Error{}} = insert_record(payload_json: "not-json")
  end

  test "rejects records with a non-positive schema version" do
    assert {:error, %Exqlite.Error{}} = insert_record(schema_version: 0)
  end

  test "rejects records with a payload checksum that is not exactly 64 characters" do
    assert {:error, %Exqlite.Error{}} = insert_record(payload_sha256: "too-short")
  end

  test "rejects duplicate record_type/record_key pairs without an explicit upsert" do
    assert {:ok, _result} = insert_record(record_key: "user-ddl-dup")
    assert {:error, %Exqlite.Error{}} = insert_record(record_key: "user-ddl-dup")
  end

  test "refuses to reverse once migration evidence exists" do
    now_iso = now()

    assert {:ok, _result} =
             SqliteRepo.query(
               """
               INSERT INTO bnest_migration_runs
                 (migration_id, source_fingerprint, ddl_checksum, state, started_at)
               VALUES (?, ?, ?, ?, ?)
               """,
               [
                 "flat-files-v1-to-sqlite-v1",
                 String.duplicate("f", 64),
                 String.duplicate("d", 64),
                 "inventoried",
                 now_iso
               ]
             )

    assert_raise RuntimeError, ~r/refuses to reverse/, fn -> migrate(:down) end
  end

  defp migrate(direction) do
    path = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
    Ecto.Migrator.with_repo(SqliteRepo, &Ecto.Migrator.run(&1, path, direction, all: true))
  end

  defp insert_record(overrides) do
    defaults = [
      record_type: "theme",
      record_key: "user-ddl-test",
      owner_id: nil,
      schema_version: 1,
      revision: nil,
      payload_json: "{}",
      payload_sha256: String.duplicate("0", 64),
      inserted_at: now(),
      updated_at: now()
    ]

    values =
      Enum.map(defaults, fn {key, default_value} -> Keyword.get(overrides, key, default_value) end)

    SqliteRepo.query(@insert_record_sql, values)
  end

  defp schema_snapshot do
    %{rows: rows} =
      SqliteRepo.query!(
        "SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name"
      )

    rows
  end

  defp schema_object_names, do: Enum.map(schema_snapshot(), fn [_type, name, _sql] -> name end)

  defp schema_migration_versions do
    %{rows: rows} = SqliteRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    rows
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
