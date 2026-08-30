defmodule BnestApp.ScheduledBackupTest do
  use ExUnit.Case, async: false

  alias BnestApp.Backup.Config
  alias BnestApp.Backup.Location
  alias BnestApp.Backup.Run
  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler.Store
  alias BnestApp.Storage.Config, as: StorageConfig
  alias BnestApp.TestRuntimeRoot

  @now ~U[2026-08-30 20:00:00Z]

  setup do
    runtime = TestRuntimeRoot.create!("scheduled-backup")
    database_directory = Path.join(runtime.sqlite_path, "database")
    temporary_root = canonical_temporary_root()
    backup_directory = Path.join(temporary_root, "bnest-backup-#{runtime.run_id}")
    config_path = Path.join(temporary_root, "bnest-backup-config-#{runtime.run_id}.json")
    storage_config_path = Path.join(runtime.path, "storage-config/storage.json")
    System.put_env("BNEST_BACKUP_CONFIG", config_path)
    System.put_env("BNEST_STORAGE_CONFIG", storage_config_path)
    {:ok, _storage} = StorageConfig.persist_directory(database_directory)
    :ok = StorageCoordinator.ensure_started!(Path.join(database_directory, "bnest.sqlite3"))
    :ok = PersistentSchedules.apply_and_verify!(@now)
    StorageConfig.activate_sqlite_primary!()

    on_exit(fn ->
      StorageCoordinator.stop()
      System.delete_env("BNEST_BACKUP_CONFIG")
      System.delete_env("BNEST_STORAGE_CONFIG")
      File.rm_rf(backup_directory)
      File.rm(config_path)
      TestRuntimeRoot.cleanup!(runtime)
    end)

    %{backup_directory: backup_directory, runtime: runtime}
  end

  test "resolves the ignored default from the runtime repository checkout", context do
    repository = Path.join(context.runtime.path, "release-checkout")
    File.mkdir_p!(repository)
    File.write!(Path.join(repository, ".gitignore"), "/data/*\n")
    {_output, 0} = System.cmd("git", ["init", "--quiet", repository])
    previous_root = System.get_env("BNEST_REPOSITORY_ROOT")
    System.put_env("BNEST_REPOSITORY_ROOT", repository)

    on_exit(fn ->
      case previous_root do
        nil -> System.delete_env("BNEST_REPOSITORY_ROOT")
        root -> System.put_env("BNEST_REPOSITORY_ROOT", root)
      end
    end)

    expected = Path.join(repository, "data/backup")
    assert Config.default_directory() == expected
    assert {:ok, %{directory: ^expected}} = Config.resolve()
  end

  test "writes and independently verifies one private owned pair", context do
    assert {:ok, location} = Config.save(context.backup_directory)

    assert {:ok, claim} =
             Store.claim_setup("prod-sqlite-backup-daily", location.destination_id, @now)

    assert {:ok, receipt} = Run.execute(claim, @now)
    assert receipt["quickCheck"] == "ok"
    assert File.exists?(Path.join(context.backup_directory, receipt["artifactBasename"]))
    refute inspect(receipt) =~ context.backup_directory
  end

  test "retains one owned pair per current seven WIB dates and preserves unknown files",
       context do
    assert {:ok, location} = Config.save(context.backup_directory)
    unknown = Path.join(context.backup_directory, "keep-me.txt")
    File.write!(unknown, "synthetic")

    Enum.each(0..8, fn days ->
      at = DateTime.add(@now, -days * 86_400)

      {:ok, claim} =
        Store.claim_setup("prod-sqlite-backup-daily", "#{location.destination_id}-#{days}", at)

      assert {:ok, _receipt} = Run.execute(claim, at)
    end)

    assert File.exists?(unknown)
    assert Run.owned_receipts(context.backup_directory) |> length() == 7
  end

  test "a destination change skips a stale setup claim", context do
    assert {:ok, first} = Config.save(context.backup_directory)
    {:ok, claim} = Store.claim_setup("prod-sqlite-backup-daily", first.destination_id, @now)
    second_directory = context.backup_directory <> "-second"
    assert {:ok, _second} = Config.save(second_directory)
    assert {:skipped, :destination_changed} = Run.execute(claim, @now)
    refute File.exists?(Path.join(second_directory, claim.run_id <> ".sqlite3"))
  end

  test "rejects relative, repository, config, source, and symlink destinations", context do
    assert {:error, :not_absolute} = Location.validate("relative/backup")

    repository_path = Path.join(File.cwd!(), "apps/bnest-app/data")
    assert {:error, :repository_path} = Location.validate(repository_path)

    config_directory = System.fetch_env!("BNEST_BACKUP_CONFIG") |> Path.dirname()
    assert {:error, :config_overlap} = Location.validate(config_directory)

    source_directory = StorageConfig.resolved_database_path() |> Path.dirname()
    assert {:error, :source_overlap} = Location.validate(source_directory)

    link = context.backup_directory <> "-link"
    File.mkdir_p!(context.backup_directory)
    File.ln_s!(context.backup_directory, link)
    assert {:error, :symlink} = Location.validate(Path.join(link, "nested"))
  end

  defp canonical_temporary_root do
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    String.trim(resolved)
  end
end
