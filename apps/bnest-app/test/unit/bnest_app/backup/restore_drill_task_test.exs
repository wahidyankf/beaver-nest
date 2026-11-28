defmodule BnestApp.Backup.RestoreDrillTaskTest do
  # `async: false`: the task reaches Backup's in-memory adapters, which the test installs
  # under their module names as the unit layer's configuration selects them.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore
  alias BnestApp.Test.InMemory.DatabaseSnapshot
  alias BnestApp.Test.InMemory.IgnoreCheck
  alias BnestApp.Test.RestoreDrill
  alias Mix.Tasks.Bnest.Backup.RestoreDrill, as: DrillTask

  @destination "/srv/test-user-backup/restore-drill"

  setup do
    _artifacts = ArtifactStore.install()
    snapshot = DatabaseSnapshot.install()
    _ignore = IgnoreCheck.install()
    _config = BackupConfigStore.install()
    {:ok, _location} = Backup.save_destination(@destination)

    context = RestoreDrill.prepare(%{backup_directory: @destination}, :drill_artifact, [])

    %{snapshot: snapshot, artifact: artifact(context)}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: The drill leaves the destination unchanged and removes its root
  test "leaves the destination unchanged and removes its root", context do
    artifacts = ArtifactStore.new()
    before = Agent.get(artifacts.pid, & &1)

    result = DrillTask.execute(["--artifact", context.artifact])

    assert result.exit_status == 0
    assert List.last(result.lines) == "Restore root: removed"
    assert Agent.get(artifacts.pid, & &1) == before
    assert DatabaseSnapshot.restore_roots(context.snapshot) == []
  end

  test "reports a restore root that remains once the restore is over", context do
    :ok = DatabaseSnapshot.leave_root_on_restore(context.snapshot)

    result = DrillTask.execute(["--artifact", context.artifact])

    assert result.exit_status == 1
    assert hd(result.lines) == "Restore drill: restored the artifact into a fresh isolated root"
    assert List.last(result.lines) == "Restore root: not removed"
  end

  test "ignores a restore root that was already there before the restore", context do
    :ok = DatabaseSnapshot.put_restore_roots(context.snapshot, ["bnest-restore-earlier"])

    result = DrillTask.execute(["--artifact", context.artifact])

    assert result.exit_status == 0
    assert List.last(result.lines) == "Restore root: removed"
    assert DatabaseSnapshot.restore_roots(context.snapshot) == ["bnest-restore-earlier"]
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: The drill without exactly one artifact name raises its usage line
  test "refuses a wrong argument list before it touches anything" do
    for arguments <- [[], ["--artifact"], ["--folder", "one"], ["--artifact", "one", "two"]] do
      assert_raise Mix.Error, "usage: mix bnest.backup.restore_drill --artifact <basename>", fn ->
        DrillTask.run(arguments)
      end
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: The drill reports an unreadable destination as one fixed line
  test "reports a destination that was never prepared as one it could not read" do
    _config = BackupConfigStore.install()

    assert DrillTask.execute([
             "--artifact",
             "bnest-prod-20300518T190100Z-test-restore-drill.sqlite3"
           ]) ==
             %{
               exit_status: 1,
               lines: ["Restore drill: the backup destination could not be read."]
             }
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: The drill refuses an artifact cut short of its last bytes
  test "refuses an artifact cut short of its last bytes with only the not-restored line",
       context do
    RestoreDrill.prepare(%{backup_directory: @destination}, :drill_artifact_cut_short, [])

    assert DrillTask.execute(["--artifact", context.artifact]) == %{
             exit_status: 1,
             lines: ["Restore drill: the artifact could not be restored."]
           }
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: The drill refuses a target that is not a regular file inside the destination
  test "refuses a target that is not a regular file inside the destination" do
    context =
      %{backup_directory: @destination}
      |> RestoreDrill.prepare(:drill_artifact, [])
      |> RestoreDrill.prepare(:drill_outside_file, [])
      |> RestoreDrill.prepare(:drill_directory, [])
      |> RestoreDrill.prepare(:drill_symlink, [])

    for argument <- [
          context.drill.outside_path,
          context.drill.directory_path |> String.split("/") |> List.last(),
          context.drill.link_path |> String.split("/") |> List.last()
        ] do
      assert DrillTask.execute(["--artifact", argument]) == %{
               exit_status: 1,
               lines: [
                 "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
               ]
             },
             "expected only the refusal line for #{inspect(argument)}"
    end
  end

  defp artifact(context),
    do: context.drill.artifact_path |> String.split("/") |> List.last()
end
