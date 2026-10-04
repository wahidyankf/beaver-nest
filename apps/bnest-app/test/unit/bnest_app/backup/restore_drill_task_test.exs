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

  defp artifact(context),
    do: context.drill.artifact_path |> String.split("/") |> List.last()
end
