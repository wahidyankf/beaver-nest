defmodule BnestApp.BackupReconcileTaskTest do
  # Each case runs the task as the standalone process it is in production, over an isolated
  # copy of a ledger and destination built here: the task starts no application, so the test
  # VM, whose application already runs a Scheduler, could not show that none is started.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.ScheduledBackupTask
  alias BnestApp.Backup.Domain.Location
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.TestRuntimeRoot
  alias Mix.Tasks.Bnest.Backup.Reconcile

  @now ~U[2026-08-30 20:00:00Z]
  @summary "Backup files: all 3 retained backups are present"
  @could_not_check "Backup files: could not be checked. Run mix bnest.backup.reconcile on the host."
  @environment ~w(BNEST_BACKUP_CONFIG BNEST_STORAGE_CONFIG)

  # The task runs in a process of its own, as `mix bnest.backup.reconcile` does. It reports the
  # Scheduler processes alive once the task has returned or exited, then keeps its exit status.
  @run_task """
  status =
    try do
      Mix.Tasks.Bnest.Backup.Reconcile.run([])
      0
    catch
      :exit, {:shutdown, status} -> status
    end

  schedulers = [Process.whereis(BnestApp.Scheduler), Process.whereis(BnestApp.Scheduler.Tasks)]
  IO.puts("schedulers=" <> inspect(schedulers))
  if status != 0, do: exit({:shutdown, status})
  """

  setup do
    runtime = TestRuntimeRoot.create!("backup-reconcile-task")
    database_directory = Path.join(runtime.sqlite_path, "database")
    temporary_root = canonical_temporary_root()
    backup_directory = Path.join(temporary_root, "bnest-backup-#{runtime.run_id}")
    config_path = Path.join(temporary_root, "bnest-backup-config-#{runtime.run_id}.json")
    previous = Map.new(@environment, &{&1, System.get_env(&1)})

    System.put_env("BNEST_BACKUP_CONFIG", config_path)
    System.put_env("BNEST_STORAGE_CONFIG", Path.join(runtime.path, "storage-config/storage.json"))
    {:ok, _storage} = Storage.persist_directory(database_directory)
    :ok = SqliteCoordinator.ensure_started!(Path.join(database_directory, "bnest.sqlite3"))
    :ok = PersistentSchedules.apply_and_verify!(@now)
    FileConfigStore.activate_sqlite_primary!()
    {:ok, location} = Backup.save_destination(backup_directory)

    on_exit(fn ->
      SqliteCoordinator.stop()
      Enum.each(previous, fn {name, value} -> restore_environment(name, value) end)
      File.rm_rf(backup_directory)
      File.rm(config_path)
      TestRuntimeRoot.cleanup!(runtime)
    end)

    %{
      backup_directory: backup_directory,
      config_path: config_path,
      database_directory: database_directory,
      location: location,
      runtime: runtime
    }
  end

  describe "a destination holding every retained backup" do
    setup context do
      runs = Enum.map(2..0//-1, &backup!(context.location, &1))
      Map.merge(context, %{runs: runs, source: source_copy!(context)})
    end

    test "exits zero, prints the summary and no date, and starts no scheduler", context do
      {output, status} = run_task(context)

      assert status == 0, output
      assert lines(output) == [@summary, "schedulers=[nil, nil]"]
      assert_private_free(output, context)
    end

    test "reads a copy: the database and its log are byte-identical and no sidecar appears",
         context do
      before = snapshot(context.source)
      assert byte_size(before[context.source.log]) > 0

      {output, status} = run_task(context)

      assert status == 0, output
      assert hd(lines(output)) == @summary
      assert snapshot(context.source) == before
      assert File.ls!(context.source.directory) |> Enum.sort() == context.source.names
    end

    test "leaves the destination it reads as it was, its mode included", context do
      File.chmod!(context.backup_directory, 0o755)
      before = directory_state(context.backup_directory)

      {output, status} = run_task(context)

      assert status == 0, output
      assert hd(lines(output)) == @summary
      assert directory_state(context.backup_directory) == before
    end

    test "exits non-zero and names the date and state of a missing artifact", context do
      [_oldest, middle, _newest] = context.runs
      File.rm!(artifact_path(context, middle))
      File.rm!(Receipt.path(artifact_path(context, middle)))

      {output, status} = run_task(context)

      assert status != 0

      assert lines(output) |> Enum.take(2) == [
               "Backup files: 1 of 3 retained backups needs attention",
               "2026-08-30: file missing"
             ]

      assert_private_free(output, context)
    end

    test "exits non-zero and names the date and state of a changed artifact", context do
      [oldest, _middle, _newest] = context.runs
      File.write!(artifact_path(context, oldest), "tampered", [:append])

      {output, status} = run_task(context)

      assert status != 0

      assert lines(output) |> Enum.take(2) == [
               "Backup files: 1 of 3 retained backups needs attention",
               "2026-08-29: file changed"
             ]

      assert_private_free(output, context)
    end

    test "exits non-zero when the destination cannot be read", context do
      File.rm_rf!(context.backup_directory)
      File.write!(context.backup_directory, "synthetic file where the destination was")

      {output, status} = run_task(context)

      assert status != 0
      assert hd(lines(output)) == @could_not_check
      assert_private_free(output, context)
    end

    test "does not create a missing destination: it reports it could not be checked", context do
      File.rm_rf!(context.backup_directory)

      {output, status} = run_task(context)

      assert status != 0
      assert hd(lines(output)) == @could_not_check
      assert_private_free(output, context)
      refute File.exists?(context.backup_directory)
    end

    test "does not mark, restrict or add to a destination it reads", context do
      marker = Location.marker_path(context.backup_directory)
      File.chmod!(context.backup_directory, 0o755)
      File.rm!(marker)
      before = directory_state(context.backup_directory)

      {output, status} = run_task(context)

      assert status != 0
      assert hd(lines(output)) == @could_not_check
      assert_private_free(output, context)
      refute File.exists?(marker)
      assert directory_state(context.backup_directory) == before
    end

    test "exits non-zero when the ledger cannot be read", context do
      File.write!(context.source.database, "synthetic bytes that are no database")
      File.rm!(context.source.log)

      {output, status} = run_task(context)

      assert status != 0
      assert hd(lines(output)) == @could_not_check
      assert_private_free(output, context)
    end

    test "exits non-zero with a path-free reason when the ledger changes between copies",
         context do
      {output, status} = run_task(context, "BnestApp.Test.DriftingLedgerCopy.install!()\n")

      assert status != 0
      assert hd(lines(output)) == @could_not_check
      assert output =~ "ledger unstable"
      assert_private_free(output, context)
    end
  end

  describe "a ledger holding no verified backup" do
    setup context, do: Map.put(context, :source, source_copy!(context))

    test "says there is nothing to check, never present, and exits non-zero", context do
      {output, status} = run_task(context)

      assert status != 0

      assert lines(output) == [
               "Backup files: no verified backup to check yet",
               "schedulers=[nil, nil]"
             ]

      refute output =~ ~r/present/i
      refute output =~ ~r/\d{4}-\d{2}-\d{2}/
    end
  end

  test "refuses an argument before it touches anything" do
    assert_raise Mix.Error, ~r/usage: mix bnest.backup.reconcile/, fn ->
      Reconcile.run(["--unexpected"])
    end
  end

  # One backup, `days_ago` days before the suite's clock, as the Scheduler would run it:
  # claimed, executed by the task and recorded verified.
  defp backup!(location, days_ago) do
    at = DateTime.add(@now, -days_ago * 86_400)

    {:ok, claim} =
      Scheduler.claim_setup(
        "prod-sqlite-backup-daily",
        "#{location.destination_id}-#{days_ago}",
        at
      )

    {:ok, receipt} = ScheduledBackupTask.execute(claim, at)
    %{claim: claim, receipt: receipt}
  end

  defp artifact_path(context, run),
    do: Path.join(context.backup_directory, run.receipt["artifactBasename"])

  # What a production database looks like to the task while the service writes to it: the
  # database file and its write-ahead log, copied from the isolated database and left in a
  # directory of their own that nothing opens, named by a storage pointer.
  defp source_copy!(context) do
    live = Path.join(context.database_directory, "bnest.sqlite3")
    directory = Path.join(context.runtime.sqlite_path, "source")
    database = Path.join(directory, "bnest.sqlite3")
    pointer = Path.join(context.runtime.path, "source-pointer/storage.json")
    File.mkdir_p!(directory)
    File.mkdir_p!(Path.dirname(pointer))
    File.cp!(live, database)
    File.cp!(live <> "-wal", database <> "-wal")

    File.write!(
      pointer,
      JSON.encode!(%{
        "schemaVersion" => 1,
        "databaseDirectory" => directory,
        "databaseFilename" => "bnest.sqlite3",
        "phase" => "sqlite_primary",
        "migrationId" => "flat-files-v1-to-sqlite-v1"
      })
    )

    %{
      directory: directory,
      database: database,
      log: database <> "-wal",
      names: ["bnest.sqlite3", "bnest.sqlite3-wal"],
      pointer: pointer
    }
  end

  # A directory as a reader can leave it changed: its mode and each entry's name, mode and bytes.
  defp directory_state(directory) do
    entries =
      for name <- File.ls!(directory) |> Enum.sort() do
        path = Path.join(directory, name)
        {name, File.stat!(path).mode, File.read!(path)}
      end

    {File.stat!(directory).mode, entries}
  end

  defp snapshot(source),
    do: %{source.database => File.read!(source.database), source.log => File.read!(source.log)}

  defp run_task(context, preamble \\ "") do
    System.cmd("mix", ["run", "--no-start", "--no-compile", "-e", preamble <> @run_task],
      cd: Path.expand("../../../..", __DIR__),
      env: [
        {"MIX_ENV", "test"},
        {"BNEST_TEST_LAYER", "integration"},
        {"BNEST_TEST_RUN_ID", context.runtime.run_id},
        {"BNEST_STORAGE_CONFIG", context.source.pointer},
        {"BNEST_BACKUP_CONFIG", context.config_path},
        {"BNEST_RUNTIME_ROOT", nil},
        {"BNEST_REPOSITORY_ROOT", nil}
      ],
      stderr_to_stdout: true
    )
  end

  defp lines(output), do: output |> String.split("\n", trim: true)

  # The destination's path and identifier, and each run's ID, artifact name and digest, or
  # any other path or digest, are what a report must never carry.
  defp assert_private_free(output, context) do
    runs = Map.get(context, :runs, [])

    private =
      [context.backup_directory, context.location.destination_id] ++
        Enum.flat_map(runs, &[&1.claim.run_id, &1.receipt["artifactBasename"]])

    refute Enum.any?(private, &String.contains?(output, &1))
    refute output =~ ~r/[0-9a-f]{64}/
    refute output =~ ~r{(?:^|[\s"'(=:])/[\w.~-]}
  end

  defp restore_environment(name, nil), do: System.delete_env(name)
  defp restore_environment(name, value), do: System.put_env(name, value)

  defp canonical_temporary_root do
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    String.trim(resolved)
  end
end
