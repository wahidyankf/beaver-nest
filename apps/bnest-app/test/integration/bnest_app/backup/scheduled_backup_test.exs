defmodule BnestApp.ScheduledBackupTest do
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.ScheduledBackupTask
  alias BnestApp.FamilyChat
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.TestBackupDestination
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
    {:ok, _storage} = Storage.persist_directory(database_directory)
    :ok = SqliteCoordinator.ensure_started!(Path.join(database_directory, "bnest.sqlite3"))
    :ok = PersistentSchedules.apply_and_verify!(@now)
    FileConfigStore.activate_sqlite_primary!()

    on_exit(fn ->
      SqliteCoordinator.stop()
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
    # As in production, which never sets the test run's own `:backup_repository_root`, so the
    # deployment's `BNEST_REPOSITORY_ROOT` names the runtime checkout; here an isolated one.
    previous_setting = Application.fetch_env(:bnest_app, :backup_repository_root)
    Application.delete_env(:bnest_app, :backup_repository_root)

    on_exit(fn ->
      case previous_root do
        nil -> System.delete_env("BNEST_REPOSITORY_ROOT")
        root -> System.put_env("BNEST_REPOSITORY_ROOT", root)
      end

      with {:ok, setting} <- previous_setting,
           do: Application.put_env(:bnest_app, :backup_repository_root, setting)
    end)

    expected = Path.join(repository, "data/backup")
    assert Backup.default_directory() == expected
    assert {:ok, %{directory: ^expected}} = Backup.destination()
  end

  test "writes and independently verifies one private owned pair", context do
    assert {:ok, location} = Backup.save_destination(context.backup_directory)

    assert {:ok, claim} =
             Scheduler.claim_setup("prod-sqlite-backup-daily", location.destination_id, @now)

    assert {:ok, receipt} = ScheduledBackupTask.execute(claim, @now)
    assert receipt["quickCheck"] == "ok"
    assert File.exists?(Path.join(context.backup_directory, receipt["artifactBasename"]))
    refute inspect(receipt) =~ context.backup_directory
  end

  test "retains one owned pair per current seven WIB dates and preserves unknown files",
       context do
    assert {:ok, location} = Backup.save_destination(context.backup_directory)
    unknown = Path.join(context.backup_directory, "keep-me.txt")
    File.write!(unknown, "synthetic")

    Enum.each(0..8, fn days ->
      at = DateTime.add(@now, -days * 86_400)

      {:ok, claim} =
        Scheduler.claim_setup(
          "prod-sqlite-backup-daily",
          "#{location.destination_id}-#{days}",
          at
        )

      assert {:ok, _receipt} = ScheduledBackupTask.execute(claim, at)
    end)

    assert File.exists?(unknown)
    assert Backup.owned_receipts(context.backup_directory) |> length() == 7
  end

  test "a destination change skips a stale setup claim", context do
    assert {:ok, first} = Backup.save_destination(context.backup_directory)
    {:ok, claim} = Scheduler.claim_setup("prod-sqlite-backup-daily", first.destination_id, @now)
    second_directory = context.backup_directory <> "-second"
    assert {:ok, _second} = Backup.save_destination(second_directory)
    assert {:skipped, :destination_changed} = ScheduledBackupTask.execute(claim, @now)
    refute File.exists?(Path.join(second_directory, claim.run_id <> ".sqlite3"))
  end

  test "rejects relative, repository, config, source, and symlink destinations", context do
    assert {:error, :not_absolute} = Backup.validate_destination("relative/backup")

    # The repository is an isolated one, `<root>/data/backup` its default: the test run's own
    # root is never a checkout.
    default = TestBackupDestination.default_repository!("repository-path")

    repository_path =
      default |> Path.dirname() |> Path.dirname() |> Path.join("apps/bnest-app/data")

    assert {:error, :repository_path} = Backup.validate_destination(repository_path)

    config_directory = System.fetch_env!("BNEST_BACKUP_CONFIG") |> Path.dirname()
    assert {:error, :config_overlap} = Backup.validate_destination(config_directory)

    source_directory = FileConfigStore.resolved_database_path() |> Path.dirname()
    assert {:error, :source_overlap} = Backup.validate_destination(source_directory)

    link = context.backup_directory <> "-link"
    File.mkdir_p!(context.backup_directory)
    File.ln_s!(context.backup_directory, link)
    assert {:error, :symlink} = Backup.validate_destination(Path.join(link, "nested"))
  end

  # The SQLite snapshot's restore reads only the active room, so an archived room, which the
  # schema can represent, never turns a restore into a failure. The room is the archived
  # second room the reply scenarios use, soft-deleted from the start; `INSERT OR IGNORE`
  # with its fixed ID keeps the run's shared Family Chat database idempotent.
  test "restores the active room of a real snapshot even when an archived room exists",
       context do
    FamilyChat.ensure_ready!()
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO family_chat_rooms (
        id, slug, name, room_kind, member_posting_enabled,
        created_at, created_by, updated_at, updated_by, deleted_at, deleted_by
      ) VALUES (900, 'ruang-arsip', 'Ruang Arsip', 'conversation', 1, ?, 'test', ?, 'test', ?, 'test')
      """,
      [now, now, now]
    )

    {:ok, location} = Backup.save_destination(context.backup_directory)

    {:ok, artifact} =
      Backup.run(deadline: @now, destination_directory: location.directory)

    assert {:ok, %{evidence: evidence}} = Backup.restore(artifact)
    assert %{"room" => room} = Jason.decode!(evidence)
    assert room["slug"] == FamilyChat.canonical_room_slug()
    refute room["slug"] == "ruang-arsip"
  end

  defp canonical_temporary_root do
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    String.trim(resolved)
  end
end
