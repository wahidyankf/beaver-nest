defmodule BnestApp.SqliteStorageMigrationTest do
  use ExUnit.Case, async: false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig
  alias BnestApp.Storage.Migration, as: StorageMigration
  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("sqlite-storage-backfill")
    database_path = Path.join(runtime.path, "bnest.sqlite3")
    pointer_directory = Path.join(runtime.path, "pointer")
    File.mkdir_p!(pointer_directory)
    System.put_env("BNEST_STORAGE_CONFIG", Path.join(pointer_directory, "storage.json"))

    seed_flat_fixtures!(runtime.path)

    :ok = StorageCoordinator.ensure_started!(database_path)
    {:ok, _versions, _apps} = migrate(:up)

    on_exit(fn ->
      StorageCoordinator.stop()
      System.delete_env("BNEST_STORAGE_CONFIG")
      TestRuntimeRoot.cleanup!(runtime)
    end)

    %{flat_root: runtime.path, database_path: database_path}
  end

  test "backfills every recognized flat-file record with immutable checksum evidence", %{
    flat_root: flat_root
  } do
    result = StorageMigration.run(flat_root)

    assert result.accepted == 2
    assert result.blocked == 0
    assert result.unsupported == 0
    assert result.state == "copying"
    assert result.migration_id == StorageMigration.migration_id()

    refute StorageMigration.blocked?()
    assert StorageMigration.integrity_ok?()
    assert StorageMigration.parity_ok?(flat_root)

    %{rows: rows} =
      SqliteRepo.query!(
        "SELECT source_sha256, target_sha256 FROM bnest_migration_items WHERE outcome = 'accepted'"
      )

    assert length(rows) == 2
    assert Enum.all?(rows, fn [source, target] -> is_binary(source) and is_binary(target) end)
  end

  test "retrying the same migration identifier does not rewrite or duplicate accepted items", %{
    flat_root: flat_root
  } do
    first = StorageMigration.run(flat_root)

    %{rows: [[items_after_first]]} =
      SqliteRepo.query!("SELECT count(*) FROM bnest_migration_items")

    second = StorageMigration.run(flat_root)

    %{rows: [[items_after_second]]} =
      SqliteRepo.query!("SELECT count(*) FROM bnest_migration_items")

    assert first.accepted == 2
    assert second.accepted == 2
    assert items_after_first == items_after_second
    assert items_after_first == 2
  end

  test "an isolated restore rehearsal proves the database without mutating the live copy", %{
    flat_root: flat_root,
    database_path: database_path
  } do
    StorageMigration.run(flat_root)
    destination = Path.join(Path.dirname(database_path), "restore-rehearsal.sqlite3")

    assert StorageMigration.restore_rehearsal(destination)
    refute File.exists?(destination)
    assert StorageMigration.parity_ok?(flat_root)
    assert StorageMigration.integrity_ok?()
  end

  test "activation switches the phase to sqlite_primary and marks the run verified", %{
    flat_root: flat_root
  } do
    StorageConfig.ensure_default!()
    StorageMigration.run(flat_root)

    assert StorageConfig.phase() == :flat_primary

    assert :ok = StorageMigration.activate!()

    assert StorageConfig.phase() == :sqlite_primary

    %{rows: [[state]]} =
      SqliteRepo.query!("SELECT state FROM bnest_migration_runs WHERE migration_id = ?", [
        StorageMigration.migration_id()
      ])

    assert state == "verified"
  end

  test "a source that changes after inventory blocks cutover with a value-free retry category", %{
    flat_root: flat_root
  } do
    first = StorageMigration.run(flat_root)
    assert first.accepted == 2
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

    :ok
  end

  defp write_fixture!(root, relative_path, record) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(record))
  end

  defp unique_suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
end
