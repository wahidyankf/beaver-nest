defmodule BnestApp.Backup.ScheduledBackupRaiseTest do
  # A scheduled run whose post-run reconciliation raises still records verified: the check
  # is only reported, never acted on. The unit layer drives the real task against the
  # in-memory doubles, with the unreadable-artifact seam standing in for the disk error.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.ScheduledBackupTask
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore
  alias BnestApp.Test.InMemory.CapacityProbe
  alias BnestApp.Test.InMemory.DatabaseSnapshot
  alias BnestApp.Test.InMemory.IgnoreCheck
  alias BnestApp.Test.InMemory.RoomStore
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestApp.Test.UnreadableArtifactStore

  @now ~U[2026-09-18 00:00:00Z]
  @before ~U[2026-09-17 00:00:00Z]
  @destination "/srv/test-user-backup/destination"

  setup do
    RoomStore.install()
    artifacts = ArtifactStore.install()
    DatabaseSnapshot.install()
    CapacityProbe.install()
    IgnoreCheck.install()
    BackupConfigStore.install()
    store = InMemoryScheduleStore.install()

    :ok =
      InMemoryScheduleStore.put_daily_schedule(
        store,
        "prod-sqlite-backup-daily",
        "prod_sqlite_backup",
        "admin_system",
        @now
      )

    {:ok, location} = Backup.save_destination(@destination)
    %{artifacts: artifacts, location: location}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: A reconciliation that raises leaves the backup verified
  test "a reconciliation that raises leaves the run verified and logs one path-free error",
       context do
    # The two runs land on different WIB dates, so retention always expects the first
    # run too: sharing one instant would let the newer run supersede it by run ID, and
    # the reconciliation would never read its artifact.
    {:ok, first_claim} =
      Scheduler.claim_setup("prod-sqlite-backup-daily", context.location.destination_id, @before)

    assert {:ok, first} = ScheduledBackupTask.execute(first_claim, @before)

    # Without its receipt the first artifact is read by reconciliation alone: backup,
    # receipt writing and retention never look at it. It cannot be read, as by a disk error.
    first_artifact = artifact_path(context, first)
    :ok = ArtifactStore.remove(context.artifacts, Receipt.path(first_artifact))
    :ok = UnreadableArtifactStore.install!(first_artifact)

    {:ok, second_claim} =
      Scheduler.claim_setup(
        "prod-sqlite-backup-daily",
        context.location.destination_id <> "-second",
        @now
      )

    # The telemetry event carries the same words as the log line; asserting on it instead
    # of captured logs keeps the proof deterministic when the suite logs concurrently.
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        "scheduled-backup-raise-proof",
        [[:bnest_app, :backup, :integrity]],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:integrity_event, event, measurements, metadata})
        end,
        %{}
      )

    on_exit(fn -> :telemetry.detach("scheduled-backup-raise-proof") end)

    assert {:ok, receipt} = ScheduledBackupTask.execute(second_claim, @now)

    runs = Scheduler.verified_runs("prod_sqlite_backup")

    assert Enum.any?(runs, &(&1.run_id == receipt["runId"]))

    # The pattern selects only this run's raised check: healthy checks from
    # backups other tests run concurrently carry exit status zero in their metadata.
    assert_received {:integrity_event, [:bnest_app, :backup, :integrity], %{problem_count: 0},
                     %{exit_status: 1} = metadata}

    assert metadata.exit_status == 1
    assert metadata.summary == "could not be checked."
    assert metadata.problems == []
  end

  defp artifact_path(context, receipt),
    do: Path.join(context.location.directory, receipt["artifactBasename"])
end
