defmodule BnestApp.TestInstance.SpawnTest do
  use ExUnit.Case, async: false

  # Lets `mix test --only test_instance` select this layer's switch tests; the ExBdd scenarios
  # that test_helper compiles always run regardless of the path given.
  @moduletag :test_instance

  import Phoenix.ConnTest

  alias BnestApp.Backup.Adapters.FileConfigStore, as: BackupConfigStore
  alias BnestApp.FamilyChat.Adapters.SqliteRoomStore
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.Storage.Records
  alias BnestApp.Test.MigrationFiles
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Error

  @endpoint BnestAppWeb.Endpoint
  @steps [:create, :activate, :migrate, :seed]
  @phases [:sqlite_primary, :flat_primary]

  setup do
    run = TestInstance.application_run!()
    assert TestInstance.state() == nil

    # The backup configuration is one fixed file in the run base. A spawn and a drop both remove
    # it, so every test starts and ends with it absent and the snapshots compare like with like.
    File.rm(backup_config_path(run))

    on_exit(fn ->
      case TestInstance.state() do
        nil -> :ok
        instance -> TestInstance.drop!(instance)
      end

      File.rm(backup_config_path(run))
    end)

    %{run: run}
  end

  describe "spawn!/2" do
    test "gives a real empty migrated SQLite file with the release seeds", %{run: run} do
      instance = TestInstance.spawn!(run)

      assert File.regular?(instance.paths.db_file)
      assert Storage.database_path() == instance.paths.db_file
      assert Storage.phase() == :sqlite_primary

      assert applied_versions() == MigrationFiles.versions()
      assert File.ls!(TestInstance.empty_flat_root(instance.paths)) == []

      assert %{rows: schedule_rows} =
               SqliteRepo.query!("SELECT schedule_key FROM bnest_schedules ORDER BY schedule_key")

      schedule_keys = Enum.map(schedule_rows, fn [key] -> key end)
      assert "prod-sqlite-backup-daily" in schedule_keys
      assert "family-chat-push-retention-daily" in schedule_keys

      assert %{rows: [["ruang-keluarga", "Ruang Keluarga"]]} =
               SqliteRepo.query!("SELECT slug, name FROM family_chat_rooms")

      # Empty apart from the seeds: no record, message or delivery exists yet.
      assert %{rows: [[0]]} = SqliteRepo.query!("SELECT count(*) FROM bnest_records")
      assert %{rows: [[0]]} = SqliteRepo.query!("SELECT count(*) FROM family_chat_messages")

      assert :ok = TestInstance.drop!(instance)
    end

    test "imports nothing from the shared flat base", %{run: run} do
      # A legacy source left in the base, as an earlier test may do. A spawn must not import it.
      stray_directory = Path.join(run.path, "users/test-user-stray/legacy/import-1")
      File.mkdir_p!(stray_directory)
      File.write!(Path.join(stray_directory, "source.bin"), "synthetic legacy bytes")
      on_exit(fn -> File.rm_rf!(Path.join(run.path, "users/test-user-stray")) end)

      instance = TestInstance.spawn!(run)

      assert %{rows: [[0]]} = SqliteRepo.query!("SELECT count(*) FROM bnest_recovery_sources")
      assert %{rows: [[0]]} = SqliteRepo.query!("SELECT count(*) FROM bnest_records")

      assert :ok = TestInstance.drop!(instance)
    end

    test "points the running server's storage at the instance generation", %{run: run} do
      instance = TestInstance.spawn!(run)

      assert Storage.database_generation() == instance.paths.generation

      body = build_conn() |> get("/health/ready") |> json_response(200)
      assert body["sqliteReady"] == true
      assert body["storageGeneration"] == "test-" <> instance.instance_id

      assert :ok = TestInstance.drop!(instance)
    end

    test "uses the same storage pointer file that FileConfigStore reads", %{run: run} do
      instance = TestInstance.spawn!(run)

      assert FileConfigStore.pointer_path() == instance.paths.storage_pointer_path

      assert {:ok, %{"databaseDirectory" => directory, "databaseGeneration" => generation}} =
               FileConfigStore.read()

      assert directory == instance.paths.db_directory
      assert generation == instance.paths.generation

      assert :ok = TestInstance.drop!(instance)
    end

    test "gives consecutive cycles disjoint databases", %{run: run} do
      first = TestInstance.spawn!(run)

      assert {:ok, _record} =
               Records.put_new(:account, "user-test-disjoint", account("user-test-disjoint"))

      assert {:ok, _record} = Records.read(:account, "user-test-disjoint")
      assert :ok = TestInstance.drop!(first)

      second = TestInstance.spawn!(run)

      refute second.instance_id == first.instance_id
      assert {:error, :missing} = Records.read(:account, "user-test-disjoint")

      assert :ok = TestInstance.drop!(second)
    end

    test "refuses a second spawn while an instance is current, and changes nothing", %{run: run} do
      instance = TestInstance.spawn!(run)
      before = snapshot()

      error = assert_raise Error, fn -> TestInstance.spawn!(run) end

      assert error.reason == :instance_active
      assert TestInstance.state() == instance
      assert snapshot() == before

      assert :ok = TestInstance.drop!(instance)
    end

    test "a spawn that cannot take the switch lock is refused as active and changes nothing", %{
      run: run
    } do
      before = snapshot()
      parent = self()

      # The switch lock is `:global` on `{BnestApp.TestInstance, :lock}`, held by the calling
      # process. This holder stands for a concurrent spawn that already holds it.
      holder =
        Task.async(fn ->
          :global.trans(
            {{TestInstance, :lock}, self()},
            fn ->
              send(parent, :lock_held)

              receive do
                :release -> :ok
              end
            end,
            [node()],
            0
          )
        end)

      assert_receive :lock_held

      try do
        error = assert_raise Error, fn -> TestInstance.spawn!(run) end

        assert error.reason == :instance_active
        assert TestInstance.state() == nil
        assert snapshot() == before
      after
        send(holder.pid, :release)
      end

      assert Task.await(holder) == :ok
    end

    test "refuses a spawn while a scheduler task runs, and creates nothing", %{run: run} do
      before = snapshot()
      {:ok, task} = start_blocking_scheduler_task()

      try do
        error = assert_raise Error, fn -> TestInstance.spawn!(run) end

        assert error.reason == :instance_busy
        assert TestInstance.state() == nil
        assert snapshot() == before
      after
        finish_blocking_scheduler_task(task)
      end
    end

    test "refuses a run that is not the application's run, and changes nothing", %{run: run} do
      before = snapshot()
      other = %{run | run_id: run.run_id <> "-other"}

      error = assert_raise Error, fn -> TestInstance.spawn!(other) end

      assert error.reason == :run_mismatch
      assert snapshot() == before
    end

    test "runs the seed hook after migration, on the new instance", %{run: run} do
      test_pid = self()

      seed = fn instance ->
        send(test_pid, {:seeded, instance.instance_id, applied_versions()})
        :ok
      end

      instance = TestInstance.spawn!(run, seed: seed)

      assert_received {:seeded, instance_id, versions}
      assert instance_id == instance.instance_id
      assert versions == MigrationFiles.versions()

      assert :ok = TestInstance.drop!(instance)
    end

    test "a backup configuration that was there before the spawn is removed", %{run: run} do
      File.mkdir_p!(Path.dirname(backup_config_path(run)))
      File.write!(backup_config_path(run), ~s({"synthetic": true}))

      instance = TestInstance.spawn!(run)

      refute File.exists?(backup_config_path(run))
      assert :ok = TestInstance.drop!(instance)
    end

    test "a spawn refused for an existing instance directory leaves the backup configuration alone",
         %{run: run} do
      existing_id = "f0e1d2c3b4a59687"
      assert {:ok, existing} = TestInstance.create_dirs(run, existing_id, :sqlite_primary)
      File.mkdir_p!(Path.dirname(backup_config_path(run)))
      File.write!(backup_config_path(run), ~s({"synthetic": true}))

      try do
        # The preflight refuses an id whose directories exist (ADR 001, section 2: 409 instance_active),
        # before anything switches, so nothing is rolled back and the backup configuration stays.
        error = assert_raise Error, fn -> TestInstance.spawn!(run, instance_id: existing_id) end

        assert error.reason == :instance_exists
        assert TestInstance.state() == nil
        assert File.exists?(backup_config_path(run))
      after
        assert :ok = TestInstance.drop_dirs(existing)
      end
    end

    test "other processes see the same current instance", %{run: run} do
      instance = TestInstance.spawn!(run)

      assert Task.async(fn -> TestInstance.state() end) |> Task.await() == instance

      assert :ok = TestInstance.drop!(instance)
    end

    for step <- @steps, phase <- @phases do
      test "a failure at #{step} in #{phase} rolls the whole spawn back", %{run: run} do
        before = snapshot()

        error =
          assert_raise Error, fn ->
            TestInstance.spawn!(run, phase: unquote(phase), fail_after: unquote(step))
          end

        assert error.reason == :spawn_failed, inspect(error)
        assert error.step == unquote(step)
        assert_rolled_back(before)
      end
    end

    test "a seed that returns an error fails the spawn at the seed step and rolls back", %{
      run: run
    } do
      before = snapshot()

      error =
        assert_raise Error, fn ->
          TestInstance.spawn!(run, seed: fn _instance -> {:error, :injected} end)
        end

      assert error.reason == :spawn_failed
      assert error.step == :seed
      assert error.detail == :injected
      assert_rolled_back(before)
    end
  end

  # A fresh installation has chosen no database location yet. The storage setup page offers the choice only then, so
  # a scenario about that choice needs an instance with no pointer and no database (ADR 001, section 1, "Phase").
  describe "spawn!/2 with unconfigured storage" do
    test "gives a flat-primary instance with no storage pointer and no database", %{run: run} do
      before = snapshot()
      instance = TestInstance.spawn!(run, phase: :flat_primary, storage: :unconfigured)

      refute File.exists?(instance.paths.storage_pointer_path)
      assert File.ls!(instance.paths.db_directory) == []
      assert Storage.phase() == :flat_primary
      assert Application.get_env(:bnest_app, :runtime_root) == instance.paths.flat_instance_root

      # A page that reads storage with no pointer opens the default location (the storage page does). It is the
      # instance's own `db/` directory, so that read can never create a database in the run base.
      assert Storage.default_directory() == instance.paths.db_directory
      assert Storage.database_path() == instance.paths.db_file

      assert {:ok, _record} =
               Records.put_new(
                 :account,
                 "user-test-unconfigured",
                 account("user-test-unconfigured")
               )

      assert :ok = TestInstance.drop!(instance)
      assert snapshot() == before
      refute File.exists?(instance.paths.flat_instance_root)
    end

    test "leaves no pointer to remove for the page that chooses the location", %{run: run} do
      instance = TestInstance.spawn!(run, phase: :flat_primary, storage: :unconfigured)

      # What the admin page does on `Create database`: it writes the first pointer, for a folder of its own.
      folder = Path.join(System.tmp_dir!(), "bnest-unconfigured-" <> instance.instance_id)
      File.mkdir!(folder)
      File.chmod!(folder, 0o700)
      on_exit(fn -> File.rm_rf!(folder) end)

      assert {:ok, %{"databaseDirectory" => ^folder}} = Storage.persist_directory(folder)
      assert File.exists?(instance.paths.storage_pointer_path)

      assert :ok = TestInstance.drop!(instance)
      refute File.exists?(instance.paths.storage_pointer_path)
    end

    test "refuses an unconfigured storage for a sqlite-primary instance and changes nothing", %{
      run: run
    } do
      before = snapshot()

      error =
        assert_raise Error, fn ->
          TestInstance.spawn!(run, phase: :sqlite_primary, storage: :unconfigured)
        end

      assert error.reason == :invalid_instance
      assert error.detail == :unconfigured_storage_needs_flat_primary
      assert snapshot() == before
    end
  end

  describe "drop!/1" do
    test "leaves no instance directory and adds nothing to the base", %{run: run} do
      # Other integration tests may write accounts into the shared base, so the base is judged by
      # what this spawn and drop add to it, not by its absolute state.
      before = snapshot()
      base_before = TestInstance.base_audit()
      instance = TestInstance.spawn!(run)

      assert :ok = TestInstance.drop!(instance)

      assert TestInstance.state() == nil
      refute File.exists?(instance.paths.sqlite_instance_root)
      refute File.exists?(instance.paths.flat_instance_root)
      assert snapshot() == before
      assert TestInstance.base_audit() == base_before
      assert Process.whereis(SqliteRepo) == nil
    end

    test "refuses an instance that is not the current one", %{run: run} do
      instance = TestInstance.spawn!(run)
      forged = %{instance | instance_id: "z9y8x7w6v5u4t3s2"}

      error = assert_raise Error, fn -> TestInstance.drop!(forged) end

      assert error.reason == :not_current
      assert TestInstance.state() == instance

      assert :ok = TestInstance.drop!(instance)
    end

    test "refuses a drop while a scheduler task runs, and keeps the instance current", %{run: run} do
      instance = TestInstance.spawn!(run)
      {:ok, task} = start_blocking_scheduler_task()

      try do
        error = assert_raise Error, fn -> TestInstance.drop!(instance) end

        assert error.reason == :instance_busy
        assert TestInstance.state() == instance
        assert Storage.database_path() == instance.paths.db_file
        assert File.dir?(instance.paths.sqlite_instance_root)
      after
        finish_blocking_scheduler_task(task)
      end

      assert :ok = TestInstance.drop!(instance)
    end

    test "a refused drop changes nothing and the instance stays current", %{run: run} do
      instance = TestInstance.spawn!(run)
      marker_path = instance.paths.sqlite_marker_path
      marker = File.read!(marker_path)
      File.rm!(marker_path)

      try do
        error = assert_raise Error, fn -> TestInstance.drop!(instance) end

        assert error.reason == :refused
        assert error.detail == :unmarked
        assert TestInstance.state() == instance
        assert Storage.database_path() == instance.paths.db_file
        assert File.dir?(instance.paths.sqlite_instance_root)
      after
        File.write!(marker_path, marker)
      end

      assert :ok = TestInstance.drop!(instance)
    end

    test "a drop whose directory removal fails restores storage and reports the retained path", %{
      run: run
    } do
      before = snapshot()
      instance = TestInstance.spawn!(run)
      root = instance.paths.sqlite_instance_root

      # Removing the children needs write access to the root, so a read-only root fails the
      # removal after the storage switch has been restored.
      File.chmod!(root, 0o500)

      try do
        error = assert_raise Error, fn -> TestInstance.drop!(instance) end

        assert error.reason == :cleanup_failed
        assert error.path == root
        assert TestInstance.state() == nil
        assert Process.whereis(SqliteRepo) == nil
        assert pointer_bytes() == before.pointer
        assert Application.fetch_env(:bnest_app, :runtime_root) == before.runtime_root
        assert File.dir?(root)
      after
        File.chmod!(root, 0o700)
      end

      assert :ok = TestInstance.drop_dirs(instance)
      assert snapshot() == before
    end

    test "restores the original runtime, backup and record store settings", %{run: run} do
      before = snapshot()
      instance = TestInstance.spawn!(run, phase: :flat_primary)

      assert Application.get_env(:bnest_app, :runtime_root) == instance.paths.flat_instance_root

      assert Application.get_env(:bnest_app, :backup_repository_root) ==
               instance.paths.backup_repository_directory

      assert :ok = TestInstance.drop!(instance)

      assert snapshot() == before
    end

    test "removes a backup configuration written during the instance", %{run: run} do
      instance = TestInstance.spawn!(run)
      store = BackupConfigStore.new()

      # The backup store writes the run base's file, which is the one each drop must remove.
      assert BackupConfigStore.config_path(store) == backup_config_path(run)
      assert :ok = BackupConfigStore.write(store, %{"synthetic" => true})
      assert File.exists?(backup_config_path(run))

      assert :ok = TestInstance.drop!(instance)
      refute File.exists?(backup_config_path(run))
    end

    test "Family Chat uses the instance database during the instance and its own path after drop",
         %{run: run} do
      original = Application.fetch_env(:bnest_app, :family_chat_sqlite_path)
      instance = TestInstance.spawn!(run)

      # Without its own path, Family Chat resolves the instance database, as production does.
      assert Application.fetch_env(:bnest_app, :family_chat_sqlite_path) == :error

      assert Enum.any?(
               SqliteRoomStore.list_active_rooms(SqliteRoomStore.new()),
               &(&1.slug == "ruang-keluarga")
             )

      assert SqliteRepo.config()[:database] == instance.paths.db_file

      assert :ok = TestInstance.drop!(instance)
      assert Application.fetch_env(:bnest_app, :family_chat_sqlite_path) == original
    end
  end

  describe "record store per phase" do
    test "a flat primary instance keeps its records out of the next instance", %{run: run} do
      first = TestInstance.spawn!(run, phase: :flat_primary)
      assert Storage.phase() == :flat_primary

      assert {:ok, _record} =
               Records.put_new(:account, "user-test-flat", account("user-test-flat"))

      assert {:ok, _record} = Records.read(:account, "user-test-flat")
      assert Path.wildcard(Path.join(first.paths.flat_instance_root, "**/*.json")) != []
      assert :ok = TestInstance.drop!(first)

      second = TestInstance.spawn!(run, phase: :flat_primary)

      assert {:error, :missing} = Records.read(:account, "user-test-flat")
      assert :ok = TestInstance.drop!(second)
    end

    test "the flat store a flat primary spawn installs is what FileRecordBackend.new!/1 builds for the instance root",
         %{run: run} do
      instance = TestInstance.spawn!(run, phase: :flat_primary)

      # The boot of a secondary BEAM builds its store the same way, from the same root.
      expected = FileRecordBackend.new!(instance.paths.flat_instance_root)
      store = :sys.get_state(Records).store

      assert store == expected
      assert store.root == instance.paths.flat_instance_root

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "audit/0 and base_audit/0" do
    test "counts a leaked instance directory and drop removes it", %{run: run} do
      count_before = TestInstance.audit().count

      assert {:ok, leaked} = TestInstance.create_dirs(run, "a1b2c3d4e5f6g7h8", :sqlite_primary)
      assert TestInstance.audit().count == count_before + 1
      assert leaked.paths.sqlite_instance_root in TestInstance.audit().directories

      assert :ok = TestInstance.drop_dirs(leaked)
      assert TestInstance.audit().count == count_before
    end

    test "reports a database file in the base", %{run: run} do
      base_before = TestInstance.base_audit()
      stray = Path.join(run.sqlite_path, "stray.sqlite3")
      File.write!(stray, "not a database")

      try do
        assert {:error, violations} = TestInstance.base_audit()
        assert Enum.any?(violations, &String.ends_with?(&1, "stray.sqlite3"))
      after
        File.rm!(stray)
      end

      assert TestInstance.base_audit() == base_before
    end
  end

  describe "drop!/1 while a scenario shadows the pointer" do
    # A scenario may set BNEST_STORAGE_CONFIG after the spawn, and a drop from any path (an adapter's end, the
    # wire cleanup, an ExBdd hook) can run then. The drop restores the run base's pointer, the path the spawn
    # checked, never the shadow; the shadow stays as the scenario set it.
    test "restores the run base pointer, not the shadow", %{run: run} do
      pointer = Application.fetch_env!(:bnest_app, :storage_config_path)
      before = File.read(pointer)
      instance = TestInstance.spawn!(run)

      shadow = Path.join(run.sqlite_path, "shadow-storage/storage.json")
      System.put_env("BNEST_STORAGE_CONFIG", shadow)
      on_exit(fn -> System.delete_env("BNEST_STORAGE_CONFIG") end)

      assert :ok = TestInstance.drop!(instance)

      assert File.read(pointer) == before
      assert System.get_env("BNEST_STORAGE_CONFIG") == shadow
      refute File.exists?(shadow)
    end
  end

  defp assert_rolled_back(before) do
    assert TestInstance.state() == nil
    assert snapshot() == before
    assert Process.whereis(SqliteRepo) == nil
  end

  defp snapshot do
    run = TestInstance.application_run!()

    %{
      audit: TestInstance.audit(),
      pointer: pointer_bytes(),
      runtime_root: Application.fetch_env(:bnest_app, :runtime_root),
      backup_repository_root: Application.fetch_env(:bnest_app, :backup_repository_root),
      family_chat_sqlite_path: Application.fetch_env(:bnest_app, :family_chat_sqlite_path),
      storage_profile: Application.fetch_env(:bnest_app, :storage_profile),
      backup_config_present: File.exists?(backup_config_path(run)),
      records_store: :sys.get_state(Records).store
    }
  end

  # The run base's backup configuration, the file `config/test.exs` points `:backup_config_path` at.
  defp backup_config_path(run), do: Path.join([run.sqlite_path, "storage-config", "backup.json"])

  defp pointer_bytes do
    case File.read(FileConfigStore.pointer_path()) do
      {:ok, bytes} -> bytes
      {:error, :enoent} -> nil
    end
  end

  defp applied_versions do
    %{rows: rows} = SqliteRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    Enum.map(rows, fn [version] -> version end)
  end

  defp start_blocking_scheduler_task do
    Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn ->
      receive do
        :release -> :ok
      end
    end)
  end

  defp finish_blocking_scheduler_task(task) do
    ref = Process.monitor(task)
    send(task, :release)
    assert_receive {:DOWN, ^ref, :process, ^task, _reason}, 1_000
    await_no_scheduler_tasks(50)
  end

  defp await_no_scheduler_tasks(0), do: flunk("scheduler task did not finish")

  defp await_no_scheduler_tasks(attempts) do
    case Task.Supervisor.children(BnestApp.Scheduler.Tasks) do
      [] ->
        :ok

      _running ->
        Process.sleep(10)
        await_no_scheduler_tasks(attempts - 1)
    end
  end

  # A synthetic account whose `userId` is the record identity, as the record stores require.
  defp account("user-" <> suffix = user_id) do
    username = "test-user-" <> suffix

    %{
      "schemaVersion" => 1,
      "recordType" => "account",
      "userId" => user_id,
      "displayUsername" => username,
      "normalizedUsername" => username,
      "roles" => ["parents"],
      "passwordVerifier" => "$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA",
      "createdAt" => Storage.now()
    }
  end
end
