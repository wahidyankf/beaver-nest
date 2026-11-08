defmodule BnestApp.TestInstance.SpawnTest do
  use ExUnit.Case, async: false

  # Lets `mix test --only test_instance` select this layer's switch tests; the ExBdd scenarios
  # that test_helper compiles always run regardless of the path given.
  @moduletag :test_instance

  import Phoenix.ConnTest

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

    on_exit(fn ->
      case TestInstance.state() do
        nil -> :ok
        instance -> TestInstance.drop!(instance)
      end
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

    test "restores the original runtime, backup and record store settings", %{run: run} do
      before = snapshot()
      instance = TestInstance.spawn!(run, phase: :flat_primary)

      assert Application.get_env(:bnest_app, :runtime_root) == instance.paths.flat_instance_root

      assert Application.get_env(:bnest_app, :backup_repository_root) ==
               instance.paths.backup_repository_directory

      assert :ok = TestInstance.drop!(instance)

      assert snapshot() == before
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

    test "FileRecordBackend.new!/1 refuses an instance root, so spawn builds the store itself", %{
      run: run
    } do
      instance = TestInstance.spawn!(run, phase: :flat_primary)

      assert_raise ArgumentError, ~r/invalid runtime root/, fn ->
        FileRecordBackend.new!(instance.paths.flat_instance_root)
      end

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

  defp assert_rolled_back(before) do
    assert TestInstance.state() == nil
    assert snapshot() == before
    assert Process.whereis(SqliteRepo) == nil
  end

  defp snapshot do
    %{
      audit: TestInstance.audit(),
      pointer: pointer_bytes(),
      runtime_root: Application.fetch_env(:bnest_app, :runtime_root),
      backup_repository_root: Application.fetch_env(:bnest_app, :backup_repository_root),
      records_store: :sys.get_state(Records).store
    }
  end

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
