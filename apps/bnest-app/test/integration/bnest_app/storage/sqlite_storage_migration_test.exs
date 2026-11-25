defmodule BnestApp.SqliteStorageMigrationTest do
  use ExUnit.Case, async: false

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Storage.Adapters.SqliteMigration
  alias BnestApp.Storage.Adapters.SqliteRecordBackend
  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Storage.Migration, as: StorageMigration
  alias BnestApp.TestRuntimeRoot
  alias Mix.Tasks.Bnest.Storage.Relocate, as: RelocateTask
  alias Mix.Tasks.Bnest.Storage.Retire, as: RetireTask

  setup do
    runtime = TestRuntimeRoot.create!("sqlite-storage-backfill")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    pointer_directory = Path.join(runtime.path, "pointer")
    File.mkdir_p!(pointer_directory)
    System.put_env("BNEST_STORAGE_CONFIG", Path.join(pointer_directory, "storage.json"))

    seed_flat_fixtures!(runtime.path)

    :ok = SqliteCoordinator.ensure_started!(database_path)
    {:ok, _versions, _apps} = migrate(:up)

    on_exit(fn ->
      SqliteCoordinator.stop()
      System.delete_env("BNEST_STORAGE_CONFIG")
      TestRuntimeRoot.cleanup!(runtime)
    end)

    %{flat_root: runtime.path, database_path: database_path}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: The storage migration task moves every recognized record and reports none blocked
  test "backfills every recognized flat-file record with immutable checksum evidence", %{
    flat_root: flat_root
  } do
    result = StorageMigration.run(flat_root)

    assert result.accepted == 4
    assert result.blocked == 0
    assert result.unsupported == 0
    assert result.state == "copying"
    assert result.migration_id == FlatMigration.migration_id()

    refute StorageMigration.blocked?()
    assert SqliteMigration.integrity_ok?()
    assert StorageMigration.parity_ok?(flat_root)

    %{rows: rows} =
      SqliteRepo.query!(
        "SELECT source_sha256, target_sha256 FROM bnest_migration_items WHERE outcome = 'accepted'"
      )

    assert length(rows) == 4
    assert Enum.all?(rows, fn [source, target] -> is_binary(source) and is_binary(target) end)

    %{rows: recovery_rows} =
      SqliteRepo.query!(
        "SELECT payload_blob, payload_sha256, byte_size FROM bnest_recovery_sources ORDER BY owner_kind"
      )

    assert length(recovery_rows) == 2

    assert Enum.all?(recovery_rows, fn [payload, checksum, size] ->
             byte_size(payload) == size and
               Base.encode16(:crypto.hash(:sha256, payload), case: :lower) == checksum
           end)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Running the storage migration task again after an interruption finishes it without duplicates
  test "retrying the same migration identifier does not rewrite or duplicate accepted items", %{
    flat_root: flat_root
  } do
    first = StorageMigration.run(flat_root)

    %{rows: [[items_after_first]]} =
      SqliteRepo.query!("SELECT count(*) FROM bnest_migration_items")

    second = StorageMigration.run(flat_root)

    %{rows: [[items_after_second]]} =
      SqliteRepo.query!("SELECT count(*) FROM bnest_migration_items")

    assert first.accepted == 4
    assert second.accepted == 4
    assert items_after_first == items_after_second
    assert items_after_first == 4
  end

  test "an isolated restore rehearsal proves the database without mutating the live copy", %{
    flat_root: flat_root,
    database_path: database_path
  } do
    StorageMigration.run(flat_root)
    destination = Path.join(Path.dirname(database_path), "restore-rehearsal.sqlite3")

    assert SqliteMigration.restore_rehearsal(destination)
    refute File.exists?(destination)
    assert StorageMigration.parity_ok?(flat_root)
    assert SqliteMigration.integrity_ok?()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: The task switches storage to SQLite only when every check passes and the app then reads from it
  test "activation switches the phase to sqlite_primary and marks the run verified", %{
    flat_root: flat_root
  } do
    FileConfigStore.ensure_default!()
    StorageMigration.run(flat_root)

    assert FileConfigStore.phase() == :flat_primary

    assert :ok = StorageMigration.activate!()

    assert FileConfigStore.phase() == :sqlite_primary

    %{rows: [[state]]} =
      SqliteRepo.query!("SELECT state FROM bnest_migration_runs WHERE migration_id = ?", [
        FlatMigration.migration_id()
      ])

    assert state == "verified"
  end

  # Once SQLite is authoritative, the operator moves it out of the configuration
  # directory: the task copies the database with proof, points the configuration at the
  # production folder, and leaves the legacy files where they were. The configuration
  # names the live database directory first, so the proof compares the database the
  # app actually reads.
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: The relocate task moves SQLite to the production data folder and keeps the old files until proof
  test "relocation moves the authoritative database and keeps the legacy files", %{
    flat_root: flat_root,
    database_path: database_path
  } do
    import ExUnit.CaptureIO

    legacy_directory = Path.dirname(database_path)
    assert {:ok, _persisted} = BnestApp.Storage.persist_directory(legacy_directory)
    StorageMigration.run(flat_root)
    assert :ok = StorageMigration.activate!()

    {:ok, before} = FileConfigStore.read()
    assert before["phase"] == "sqlite_primary"
    legacy_database = Path.join(before["databaseDirectory"], before["databaseFilename"])
    assert File.regular?(legacy_database)

    production = Path.join(before["databaseDirectory"], "production-data")

    output =
      capture_io(fn ->
        RelocateTask.run(["--destination", production])
      end)

    assert output =~ "relocation verified"

    {:ok, after_relocation} = FileConfigStore.read()
    assert after_relocation["databaseDirectory"] == production
    assert is_binary(after_relocation["databaseGeneration"])

    assert File.regular?(Path.join(production, before["databaseFilename"]))
    assert File.regular?(legacy_database)
  end

  # Once SQLite is authoritative and every flat file is verified against the migrated
  # evidence, the operator retires the legacy store: verified flat files and the legacy
  # database go, while the configuration and tracked placeholders stay. The retired
  # flat root holds only the migrated fixtures, so nothing outside the evidence can
  # block the verification.
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Verified legacy flat-file storage is retired
  test "retirement removes verified flat files and keeps configuration and placeholders",
       %{flat_root: flat_root, database_path: database_path} do
    import ExUnit.CaptureIO

    legacy_directory = Path.dirname(database_path)
    assert {:ok, _persisted} = BnestApp.Storage.persist_directory(legacy_directory)

    retired_root = Path.join(flat_root, "legacy-flat")
    File.mkdir_p!(retired_root)
    seed_flat_fixtures!(retired_root)

    StorageMigration.run(retired_root)
    assert :ok = StorageMigration.activate!()

    {:ok, pre_relocation} = FileConfigStore.read()

    production = Path.join(pre_relocation["databaseDirectory"], "production-data")

    capture_io(fn ->
      RelocateTask.run(["--destination", production])
    end)

    {:ok, config} = FileConfigStore.read()
    generation = config["databaseGeneration"]
    assert is_binary(generation)

    output =
      capture_io(fn ->
        RetireTask.run([
          "--root",
          retired_root,
          "--generation",
          generation
        ])
      end)

    assert output =~ "verified legacy storage retired"

    remaining =
      retired_root
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&(Path.basename(&1) == ".gitkeep"))

    assert remaining == []
    assert FileConfigStore.phase() == :sqlite_primary
  end

  test "verified retry preserves a newer authoritative record while reconciling sources", %{
    flat_root: flat_root
  } do
    FileConfigStore.ensure_default!()
    StorageMigration.run(flat_root)
    StorageMigration.activate!()

    relative_path = theme_relative_path(flat_root)
    ["users", user_id, "preferences", "theme.json"] = String.split(relative_path, "/")
    store = SqliteRecordBackend.new()
    {:ok, source} = SqliteRecordBackend.read(store, :theme, user_id)

    newer =
      source
      |> Map.put("theme", "light")
      |> Map.put("updatedAt", DateTime.utc_now() |> DateTime.to_iso8601())

    assert {:ok, authoritative} = SqliteRecordBackend.write(store, :theme, user_id, 0, newer)

    assert authoritative["revision"] == 1
    assert StorageMigration.run(flat_root).state == "verified"
    assert StorageMigration.parity_ok?(flat_root)

    assert {:ok, ^authoritative} = SqliteRecordBackend.read(store, :theme, user_id)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Invalid or changed source blocks cutover without data loss
  test "a source that changes after inventory blocks cutover with a value-free retry category", %{
    flat_root: flat_root
  } do
    first = StorageMigration.run(flat_root)
    assert first.accepted == 4
    assert first.blocked == 0

    theme_path = Path.join(flat_root, theme_relative_path(flat_root))

    File.write!(
      theme_path,
      Jason.encode!(%{"schemaVersion" => 1, "recordType" => "theme-preference"})
    )

    second = StorageMigration.run(flat_root)

    assert second.blocked > 0
    assert second.state == "failed"
    assert StorageMigration.blocked?()
    refute StorageMigration.parity_ok?(flat_root)
  end

  defp migrate(direction) do
    path = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
    Ecto.Migrator.with_repo(SqliteRepo, &Ecto.Migrator.run(&1, path, direction, all: true))
  end

  defp theme_relative_path(flat_root) do
    flat_root
    |> Path.join("users/*/preferences/theme.json")
    |> Path.wildcard()
    |> List.first()
    |> Path.relative_to(flat_root)
  end

  defp seed_flat_fixtures!(root) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    user_id = "user-" <> unique_suffix()

    write_fixture!(root, "system/bootstrap.json", %{
      "schemaVersion" => 1,
      "recordType" => "bootstrap",
      "state" => "closed",
      "attemptId" => "attempt-" <> unique_suffix(),
      "startedAt" => now,
      "closedAt" => now,
      "accounts" => [
        %{
          "userId" => user_id,
          "normalizedUsername" => "fixtureuser",
          "accountSha256" => String.duplicate("a", 64),
          "indexSha256" => String.duplicate("b", 64)
        }
      ]
    })

    write_fixture!(root, "users/#{user_id}/preferences/theme.json", %{
      "schemaVersion" => 1,
      "recordType" => "theme-preference",
      "ownerId" => user_id,
      "sourceImportId" => nil,
      "revision" => 0,
      "theme" => "dark",
      "updatedAt" => now
    })

    write_binary_fixture!(
      root,
      "apps/beaver-nest/legacy/import-app-backup/source.bin",
      "app recovery bytes"
    )

    write_binary_fixture!(
      root,
      "users/#{user_id}/legacy/import-user-backup/source.bin",
      "user recovery bytes"
    )

    :ok
  end

  defp write_fixture!(root, relative_path, record) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(record))
  end

  defp write_binary_fixture!(root, relative_path, bytes) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
  end

  defp unique_suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
end
