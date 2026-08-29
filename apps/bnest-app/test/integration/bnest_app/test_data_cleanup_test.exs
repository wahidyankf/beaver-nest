defmodule BnestApp.TestDataCleanupTest do
  use ExUnit.Case, async: false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config
  alias BnestApp.Storage.Migration
  alias BnestApp.Storage.TestDataCleanup
  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("legacy-test-data-cleanup")
    pointer = Path.join(runtime.path, "pointer/storage.json")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    generation = "generation-test-cleanup"
    System.put_env("BNEST_STORAGE_CONFIG", pointer)

    {:ok, _config} = Config.persist_directory(runtime.sqlite_path)
    :ok = StorageCoordinator.ensure_started!(database_path)
    {:ok, _versions, _apps} = migrate(:up)
    Migration.run(runtime.path)
    Migration.activate!()
    Config.restore!(Config.read() |> elem(1) |> Map.put("databaseGeneration", generation))

    insert_record!("account", "user-test-old", "user-test-old", %{
      "recordType" => "account",
      "userId" => "user-test-old"
    })

    insert_record!("username-index", "test-user-old", nil, %{
      "recordType" => "username-index",
      "normalizedUsername" => "test-user-old",
      "userId" => "user-test-old"
    })

    insert_record!("browser-session", "test-session", nil, %{
      "recordType" => "browser-session",
      "userId" => "user-test-old"
    })

    insert_record!("chat", "user-family", "user-family", %{
      "recordType" => "chat",
      "ownerId" => "user-family"
    })

    insert_recovery_source!("user", "user-test-old", "import-old")
    insert_recovery_source!("user", "user-synthetic", "import-user-backup")
    insert_recovery_source!("app", "beaver-nest", "import-synthetic-backup")
    insert_recovery_source!("user", "user-family", "import-family")

    on_exit(fn ->
      StorageCoordinator.stop()
      System.delete_env("BNEST_STORAGE_CONFIG")
      TestRuntimeRoot.cleanup!(runtime)
    end)

    %{generation: generation}
  end

  test "dry-run counts only reserved legacy test identities", %{generation: generation} do
    assert {:ok, %{records: 3, recovery_sources: 3}} = TestDataCleanup.verify(generation)
    assert record_count() == 4
  end

  test "purge deletes test identities and preserves family data", %{generation: generation} do
    assert {:ok, %{records: 3, recovery_sources: 3}} = TestDataCleanup.run(generation)
    assert record_count() == 1

    assert SqliteRepo.query!("SELECT record_key FROM bnest_records").rows == [["user-family"]]

    assert SqliteRepo.query!("SELECT owner_key FROM bnest_recovery_sources").rows == [
             ["user-family"]
           ]

    assert SqliteRepo.query!("PRAGMA quick_check").rows == [["ok"]]
  end

  test "generation mismatch refuses cleanup without mutation", %{generation: generation} do
    assert TestDataCleanup.run(generation <> "-wrong") == {:error, :generation_mismatch}
    assert record_count() == 4
  end

  defp migrate(direction) do
    path = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
    Ecto.Migrator.with_repo(SqliteRepo, &Ecto.Migrator.run(&1, path, direction, all: true))
  end

  defp insert_record!(record_type, record_key, owner_id, payload) do
    encoded = Jason.encode!(payload)

    SqliteRepo.query!(
      "INSERT INTO bnest_records (record_type, record_key, owner_id, schema_version, revision, payload_json, payload_sha256, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        record_type,
        record_key,
        owner_id,
        1,
        nil,
        encoded,
        Base.encode16(:crypto.hash(:sha256, encoded), case: :lower),
        timestamp(),
        timestamp()
      ]
    )
  end

  defp record_count,
    do: SqliteRepo.query!("SELECT count(*) FROM bnest_records").rows |> hd() |> hd()

  defp insert_recovery_source!(owner_kind, owner_key, import_id) do
    SqliteRepo.query!(
      "INSERT INTO bnest_recovery_sources (owner_kind, owner_key, import_id, payload_blob, payload_sha256, byte_size, inserted_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      [
        owner_kind,
        owner_key,
        import_id,
        "bytes",
        Base.encode16(:crypto.hash(:sha256, "bytes"), case: :lower),
        5,
        timestamp()
      ]
    )
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
