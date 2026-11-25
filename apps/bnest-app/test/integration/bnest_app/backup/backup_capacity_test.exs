defmodule BnestApp.BackupCapacityTest do
  # A destination without room for the snapshot is refused before anything is written, and
  # the scheduled run is recorded retryable so a later tick retries it. Only the free-space
  # reading comes from a double (no test disk can be filled on demand); destination,
  # database, snapshot, receipt, and retention are all real.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.ScheduledBackupTask
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Test.InMemory.CapacityProbe
  alias BnestApp.TestRuntimeRoot

  @now ~U[2026-08-30 20:00:00Z]

  setup do
    runtime = TestRuntimeRoot.create!("backup-capacity")
    database_directory = Path.join(runtime.sqlite_path, "database")
    temporary_root = canonical_temporary_root()
    backup_directory = Path.join(temporary_root, "bnest-backup-#{runtime.run_id}")
    config_path = Path.join(temporary_root, "bnest-backup-config-#{runtime.run_id}.json")
    storage_config_path = Path.join(runtime.path, "storage-config/storage.json")
    System.put_env("BNEST_BACKUP_CONFIG", config_path)
    System.put_env("BNEST_STORAGE_CONFIG", storage_config_path)
    {:ok, _storage} = Storage.persist_directory(database_directory)
    :ok = SqliteCoordinator.ensure_started!(Path.join(database_directory, "bnest.sqlite3"))
    :ok = PersistentSchedules.apply_and_verify!(@now)
    FileConfigStore.activate_sqlite_primary!()

    probe = CapacityProbe.install()
    backup_configuration = Application.fetch_env!(:bnest_app, Backup)

    Application.put_env(
      :bnest_app,
      Backup,
      Keyword.put(backup_configuration, :capacity_probe, CapacityProbe)
    )

    on_exit(fn ->
      Application.put_env(:bnest_app, Backup, backup_configuration)
      SqliteCoordinator.stop()
      System.delete_env("BNEST_BACKUP_CONFIG")
      System.delete_env("BNEST_STORAGE_CONFIG")
      File.rm_rf(backup_directory)
      File.rm(config_path)
      TestRuntimeRoot.cleanup!(runtime)
    end)

    %{backup_directory: backup_directory, probe: probe}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A backup is refused and retried later when the backup folder lacks free space
  test "a destination without free space is refused with no file, and runs once space returns",
       context do
    assert {:ok, location} = Backup.save_destination(context.backup_directory)

    measurement = CapacityProbe.measurement(context.probe)

    required =
      measurement.page_count * measurement.page_size + measurement.wal_bytes +
        256 * 1024 * 1024

    :ok = CapacityProbe.put_available_bytes(context.probe, required - 1)

    {:ok, refused} =
      Scheduler.claim_setup("prod-sqlite-backup-daily", location.destination_id, @now)

    assert {:error, :insufficient_capacity} = ScheduledBackupTask.execute(refused, @now)

    assert context.backup_directory
           |> File.ls!()
           |> Enum.filter(&String.contains?(&1, ".sqlite3")) == []

    :ok = CapacityProbe.put_available_bytes(context.probe, required)

    {:ok, retried} =
      Scheduler.claim_setup(
        "prod-sqlite-backup-daily",
        "#{location.destination_id}-retry",
        @now
      )

    assert {:ok, receipt} = ScheduledBackupTask.execute(retried, @now)
    assert File.regular?(Path.join(context.backup_directory, receipt["artifactBasename"]))
  end

  defp canonical_temporary_root do
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    String.trim(resolved)
  end
end
