defmodule BnestApp.BackupRestoreDrillTaskTest do
  # Two kinds of case share one isolated destination holding a synthetic SQLite artifact:
  #
  #   * `run_task/2` runs the task as the standalone process it is in production, because only
  #     a process of its own shows the exit status, the lines it prints and that it starts no
  #     repository and no Scheduler, which the test VM's application already runs;
  #   * `execute/1` runs the task's check in this VM under `BnestApp.Test.CallTrace`, which
  #     shows what it created, opened and called.
  #
  # The operating system's temporary directory is redirected to an empty directory of the case's
  # own, where a restore creates its root, so a root left behind, or one a refusal created, is a
  # listing that holds a `bnest-restore-` entry.
  use ExUnit.Case, async: false

  alias BnestApp.Backup.Ports.DatabaseSnapshot, as: SnapshotPort
  alias BnestApp.Test.CallTrace
  alias BnestApp.Test.RestoreDrill, as: Fixture
  alias BnestApp.TestBackupDestination
  alias BnestApp.TestRuntimeRoot
  alias Mix.Tasks.Bnest.Backup.RestoreDrill, as: DrillTask

  @refused "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
  @unreadable "Restore drill: the backup destination could not be read."
  @not_restored "Restore drill: the artifact could not be restored."
  @restored "Restore drill: restored the artifact into a fresh isolated root"
  @usage ~r/usage: mix bnest.backup.restore_drill --artifact <basename>/

  @digest ~r/[0-9a-f]{64}/
  @absolute_path ~r{(?:^|[\s"'(=:])/[\w.~-]}

  # What can open the live database: a connection opened by path, the repository on the live
  # file, its start-up and everything the Snapshot port serves.
  @live_database_watch [
    {{Exqlite.Sqlite3, :open, :_}, []},
    {{BnestApp.SqliteRepo, :_, :_}, []},
    {{BnestApp.Storage, :ensure_started!, :_}, []},
    {{SnapshotPort, :_, :_}, []}
  ]

  # The task runs in a process of its own, as `mix bnest.backup.restore_drill` does. It reports
  # which processes the task started once it has returned or exited, then keeps its exit status.
  @run_task """
  status =
    try do
      Mix.Tasks.Bnest.Backup.RestoreDrill.run(ARGUMENTS)
      0
    catch
      :exit, {:shutdown, status} -> status
    end

  started =
    for name <- [BnestApp.SqliteRepo, BnestApp.Scheduler, BnestApp.Scheduler.Tasks],
        Process.whereis(name),
        do: name

  IO.puts("started=" <> inspect(started))
  if status != 0, do: exit({:shutdown, status})
  """

  setup do
    runtime = TestRuntimeRoot.create!("backup-restore-drill-task")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    location = TestBackupDestination.configure!("restore-drill-task")

    context =
      Fixture.prepare(
        %{backup_directory: location.directory, backup_location: location},
        :drill_artifact,
        []
      )

    live = live_database!(runtime)

    Map.merge(context, %{
      runtime: runtime,
      live: live,
      config_path: System.get_env("BNEST_BACKUP_CONFIG"),
      artifact: Path.basename(context.drill.artifact_path)
    })
  end

  describe "as the standalone task" do
    test "restores the artifact, prints only redacted evidence and starts nothing", context do
      result = run_task(context, ["--artifact", context.artifact])

      assert result.status == 0, result.output

      assert result.lines == [
               @restored,
               "Rooms readable: 1",
               "Messages readable: 3, in ascending order",
               "Push subscriptions: 2",
               "Delivery states: delivered, pending",
               "Restore root: removed"
             ]

      assert result.started == "[]"
      assert_private_free(result.output, context)
    end

    test "leaves the destination, the live database and the temporary directory as found",
         context do
      destination = tree_state(context.backup_directory)
      live = tree_state(context.live.directory)

      result = run_task(context, ["--artifact", context.artifact])

      assert result.status == 0, result.output
      assert tree_state(context.backup_directory) == destination
      assert tree_state(context.live.directory) == live
      assert restore_roots(context) == []
    end

    test "refuses a regular file outside the destination by its absolute path, creating no root",
         context do
      outside = Fixture.prepare(context, :drill_outside_file, []).drill.outside_path
      destination = tree_state(context.backup_directory)

      result = run_task(context, ["--artifact", outside])

      assert result.status == 1, result.output
      assert result.lines == [@refused]
      assert result.started == "[]"
      assert_private_free(result.output, context)
      assert restore_roots(context) == []
      assert tree_state(context.backup_directory) == destination
      assert File.regular?(outside)
    end

    test "exits non-zero with a fixed line when the destination cannot be read", context do
      File.rm_rf!(context.backup_directory)
      File.write!(context.backup_directory, "synthetic file where the destination was")

      result = run_task(context, ["--artifact", context.artifact])

      assert result.status == 1, result.output
      assert result.lines == [@unreadable]
      assert_private_free(result.output, context)
      assert restore_roots(context) == []
    end

    test "does not create a missing destination: it reports it could not be read", context do
      File.rm_rf!(context.backup_directory)

      result = run_task(context, ["--artifact", context.artifact])

      assert result.status == 1, result.output
      assert result.lines == [@unreadable]
      refute File.exists?(context.backup_directory)
    end

    test "exits non-zero with a fixed line for an artifact that does not restore", context do
      unrestorable = "bnest-prod-20300518T190600Z-test-unrestorable.sqlite3"
      path = Path.join(context.backup_directory, unrestorable)
      File.write!(path, "synthetic bytes that are no database")
      destination = tree_state(context.backup_directory)

      result = run_task(context, ["--artifact", unrestorable])

      assert result.status == 1, result.output
      assert result.lines == [@not_restored]
      refute result.output =~ unrestorable
      assert_private_free(result.output, context)
      assert restore_roots(context) == []
      assert tree_state(context.backup_directory) == destination
    end
  end

  describe "as the task's check in this VM" do
    test "restores into a fresh marked root of the temporary directory and removes it",
         context do
      assert File.ls!(context.drill.scratch) == []

      {result, events} =
        CallTrace.record(
          [
            {{File, :mkdir_p!, :_}, []},
            {{File, :write!, :_}, []},
            {{File, :cp!, :_}, []},
            {{Exqlite.Sqlite3, :open, :_}, []}
          ],
          fn -> execute(["--artifact", context.artifact]) end
        )

      assert result.exit_status == 0
      assert List.first(result.lines) == @restored
      assert List.last(result.lines) == "Restore root: removed"

      assert [{_caller, [root]}] = CallTrace.calls(events, File, :mkdir_p!)
      assert Path.dirname(root) == context.drill.scratch
      assert String.starts_with?(Path.basename(root), "bnest-restore-")

      assert [{_caller, [marker_path, marker]}] = CallTrace.calls(events, File, :write!)
      assert marker_path == Path.join(root, ".bnest-restore-root.json")
      assert %{"ownershipScope" => "bnest-production-restores-v1"} = Jason.decode!(marker)

      copy = Path.join(root, "restored.sqlite3")
      assert [{_caller, [artifact_path, ^copy]}] = CallTrace.calls(events, File, :cp!)
      assert artifact_path == context.drill.artifact_path
      assert [{_caller, [^copy | _options]}] = CallTrace.calls(events, Exqlite.Sqlite3, :open)

      refute File.exists?(root)
      assert File.ls!(context.drill.scratch) == []
    end

    test "opens nothing but the restored copy and starts no repository", context do
      {result, events} =
        CallTrace.record(@live_database_watch, fn ->
          execute(["--artifact", context.artifact])
        end)

      assert result.exit_status == 0

      assert [{_caller, [restored_path | _options]}] =
               CallTrace.calls(events, Exqlite.Sqlite3, :open)

      assert Path.dirname(Path.dirname(restored_path)) == context.drill.scratch
      assert CallTrace.calls(events, SnapshotPort, :restore) |> length() == 1

      assert stray_calls(events, [
               {SnapshotPort, :source_path},
               {SnapshotPort, :restore},
               {SnapshotPort, :restore_roots},
               {Exqlite.Sqlite3, :open}
             ]) == []
    end

    test "reports a restore of no messages without claiming an order", context do
      context = replace_artifact(context, [0, 1, ["pending"]])

      result = execute(["--artifact", Path.basename(context.drill.artifact_path)])

      assert result.exit_status == 0

      assert result.lines == [
               @restored,
               "Rooms readable: 1",
               "Messages readable: 0",
               "Push subscriptions: 1",
               "Delivery states: pending",
               "Restore root: removed"
             ]
    end

    test "reports a restore that holds no delivery state", context do
      context = replace_artifact(context, [2, 1, []])

      result = execute(["--artifact", Path.basename(context.drill.artifact_path)])

      assert result.exit_status == 0

      assert result.lines == [
               @restored,
               "Rooms readable: 1",
               "Messages readable: 2, in ascending order",
               "Push subscriptions: 1",
               "Delivery states: none",
               "Restore root: removed"
             ]
    end

    test "reports the delivery states in sorted order", context do
      context = replace_artifact(context, [1, 3, ["pending", "failed", "sent"]])

      result = execute(["--artifact", Path.basename(context.drill.artifact_path)])

      assert result.exit_status == 0

      assert result.lines == [
               @restored,
               "Rooms readable: 1",
               "Messages readable: 1, in ascending order",
               "Push subscriptions: 3",
               "Delivery states: failed, pending, sent",
               "Restore root: removed"
             ]
    end
  end

  describe "refusals" do
    setup context do
      context =
        context
        |> Fixture.prepare(:drill_outside_file, [])
        |> Fixture.prepare(:drill_directory, [])
        |> Fixture.prepare(:drill_symlink, [])

      nested = Path.join(context.backup_directory, "nested")
      File.mkdir_p!(nested)
      File.cp!(context.drill.artifact_path, Path.join(nested, context.artifact))

      Map.put(context, :destination, tree_state(context.backup_directory))
    end

    for {name, kind} <- [
          {"a regular file outside the destination by its absolute path", :absolute},
          {"a relative path that climbs out of the destination", :climbing},
          {"a path into a directory of the destination", :nested},
          {"the parent directory", :parent},
          {"the destination itself", :current},
          {"an empty name", :empty},
          {"a name with a trailing separator", :trailing_separator},
          {"a file the destination does not hold", :missing},
          {"a directory inside the destination", :directory},
          {"a symbolic link inside the destination to a file outside it", :symlink}
        ] do
      test "refuses #{name}, creating no restore root and opening no database", context do
        argument = argument(context, unquote(kind))

        {result, events} =
          CallTrace.record(@live_database_watch, fn -> execute(["--artifact", argument]) end)

        assert result.exit_status == 1
        assert result.lines == [@refused]

        assert stray_calls(events, [{SnapshotPort, :source_path}]) == []
        assert File.ls!(context.drill.scratch) == []
        assert tree_state(context.backup_directory) == context.destination
        assert File.regular?(context.drill.outside_path)
      end
    end
  end

  test "refuses a wrong argument list before it touches anything" do
    for arguments <- [[], ["--artifact"], ["artifact.sqlite3"], ["--artifact", "a", "b"]] do
      assert_raise Mix.Error, @usage, fn -> DrillTask.run(arguments) end
    end
  end

  # The restore roots the temporary directory holds. A task run in a process of its own finds
  # Mix's lock and PubSub directories there as well, which are no restore root.
  defp restore_roots(context) do
    context.drill.scratch |> File.ls!() |> Enum.filter(&String.starts_with?(&1, "bnest-restore-"))
  end

  # The watched calls beyond `allowed`. Asking where the live database is, to keep the
  # destination clear of it, is not opening it.
  defp stray_calls(events, allowed) do
    for {:call, {module, function, _arity}, _caller, _args} <- events,
        {module, function} not in allowed,
        do: {module, function}
  end

  # The task's check without printing or exiting.
  defp execute(arguments), do: DrillTask.execute(arguments)

  # The destination's artifact, rebuilt from another synthetic fixture.
  defp replace_artifact(context, spec) do
    File.rm!(context.drill.artifact_path)
    Fixture.prepare(context, :drill_artifact, spec)
  end

  defp argument(context, :absolute), do: context.drill.outside_path

  defp argument(context, :climbing),
    do: Path.join("..", Path.basename(context.drill.outside_path))

  defp argument(context, :nested), do: Path.join("nested", context.artifact)
  defp argument(_context, :parent), do: ".."
  defp argument(_context, :current), do: "."
  defp argument(_context, :empty), do: ""
  defp argument(context, :trailing_separator), do: context.artifact <> "/"
  defp argument(_context, :missing), do: "bnest-prod-20300518T190600Z-test-absent.sqlite3"
  defp argument(context, :directory), do: Path.basename(context.drill.directory_path)
  defp argument(context, :symlink), do: Path.basename(context.drill.link_path)

  # An isolated database the task must never open, named by an isolated storage pointer: bytes
  # that are no database, so that an open which reads them would fail and one that writes
  # beside them would leave a file behind.
  defp live_database!(runtime) do
    directory = Path.join(runtime.sqlite_path, "live")
    pointer = Path.join(runtime.path, "live-pointer/storage.json")
    File.mkdir_p!(directory)
    File.mkdir_p!(Path.dirname(pointer))

    File.write!(
      Path.join(directory, "bnest.sqlite3"),
      "synthetic bytes standing for the live data"
    )

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

    %{directory: directory, pointer: pointer}
  end

  defp run_task(context, arguments) do
    code = String.replace(@run_task, "ARGUMENTS", inspect(arguments))

    {output, status} =
      System.cmd("mix", ["run", "--no-start", "--no-compile", "-e", code],
        cd: Path.expand("../../../..", __DIR__),
        env: [
          {"MIX_ENV", "test"},
          {"BNEST_TEST_LAYER", "integration"},
          {"BNEST_TEST_RUN_ID", context.runtime.run_id},
          {"BNEST_STORAGE_CONFIG", context.live.pointer},
          {"BNEST_BACKUP_CONFIG", context.config_path},
          {"BNEST_RUNTIME_ROOT", nil},
          {"BNEST_REPOSITORY_ROOT", nil},
          {"TMPDIR", context.drill.scratch}
        ],
        stderr_to_stdout: true
      )

    {lines, started} =
      output |> String.split("\n", trim: true) |> Enum.split_while(&(not started?(&1)))

    %{
      status: status,
      output: output,
      lines: lines,
      started: started |> List.first("") |> String.replace_prefix("started=", "")
    }
  end

  defp started?(line), do: String.starts_with?(line, "started=")

  # A directory as a task can leave it changed: each entry's name, mode and bytes, or its type.
  defp tree_state(directory) do
    for name <- directory |> File.ls!() |> Enum.sort() do
      path = Path.join(directory, name)

      case File.lstat!(path) do
        %File.Stat{type: :regular, mode: mode} -> {name, mode, File.read!(path)}
        %File.Stat{type: type, mode: mode} -> {name, mode, type}
      end
    end
  end

  # What the output must never carry: the destination and the artifact's path and name, the
  # temporary directory a restore root lies in, every message body, push endpoint and key, a
  # digest and any other path.
  defp assert_private_free(output, context) do
    %{spec: spec, artifact_path: artifact_path, scratch: scratch} = context.drill

    private =
      [
        context.backup_directory,
        artifact_path,
        context.artifact,
        scratch,
        context.runtime.path,
        spec.token
      ] ++
        Enum.map(spec.messages, & &1.body) ++
        Enum.flat_map(spec.subscriptions, &[&1.endpoint, &1.p256dh, &1.auth])

    refute Enum.any?(private, &String.contains?(output, &1))
    refute output =~ @digest
    refute output =~ @absolute_path
    refute output =~ "bnest-restore-"
  end
end
