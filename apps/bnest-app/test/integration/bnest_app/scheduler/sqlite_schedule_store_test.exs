defmodule BnestApp.Scheduler.SqliteScheduleStoreTest do
  # Not async: the SQLite repository is one named process, repointed for each test.
  use BnestApp.Test.Contracts.ScheduleStoreContract, async: false

  alias BnestApp.Scheduler.Adapters.SqliteScheduleStore
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Test.Seeds.Schedules
  alias BnestApp.TestRuntimeRoot

  # Each test gets its own database under an isolated test-run root, migrated to the
  # current schema with no schedule seeded: the release seeds come from
  # `PersistentSchedules` and Family Chat, which the contract replaces with its own.
  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("sqlite-schedule-store")
    :ok = SqliteCoordinator.ensure_started!(Path.join(runtime.sqlite_path, "bnest.sqlite3"))

    on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    migrations = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
    _versions = Ecto.Migrator.run(SqliteRepo, migrations, :up, all: true, log: false)
    SqliteScheduleStore.new()
  end

  defp put_schedule(_store, schedule), do: :ok = Schedules.put_schedule!(schedule)

  # A ledger row of a backup schedule in the given state, as a seeded Given states it: a
  # scheduled claim of `slot` unless `fields` makes it a setup claim.
  defp ledger_run(run_id, state, slot, fields) do
    Map.merge(
      %{
        schedule_key: "backup-daily",
        claim_key: "slot:" <> DateTime.to_iso8601(slot),
        claim_kind: "scheduled",
        scheduled_for: slot,
        run_id: run_id,
        schedule_revision: 1,
        occurrence_number: 1,
        attempt: 1,
        state: state,
        lease_expires_at: nil,
        next_attempt_at: nil,
        artifact_basename: nil,
        artifact_sha256: nil,
        artifact_bytes: nil,
        failure_category: nil,
        started_at: slot,
        finished_at: nil
      },
      fields
    )
  end

  defp artifact(name) do
    receipt = receipt(name)

    %{
      artifact_basename: receipt["artifactBasename"],
      artifact_sha256: receipt["artifactSha256"],
      artifact_bytes: receipt["artifactBytes"]
    }
  end

  test "reading verified runs leaves every stored run as it was", %{store: store} do
    put_schedule(
      store,
      schedule(%{schedule_key: "backup-daily", handler_key: "prod_sqlite_backup"})
    )

    verified = Map.merge(%{finished_at: at(60)}, artifact("night"))
    :ok = Schedules.put_run!(ledger_run("seeded-verified", "verified", slot(), verified))

    :ok =
      Schedules.put_run!(
        ledger_run("seeded-failed", "failed", DateTime.add(slot(), -86_400), %{
          failure_category: "io_failed",
          finished_at: at(90)
        })
      )

    stored = Schedules.runs()

    assert [%{run_id: "seeded-verified", slot: slot(), finished_at: at(60)}] ==
             store
             |> ScheduleStore.verified_runs("prod_sqlite_backup")
             |> Enum.map(&Map.take(&1, [:run_id, :slot, :finished_at]))

    assert Schedules.runs() == stored
  end

  test "reports a seeded verified run that has no slot with a nil slot", %{store: store} do
    put_schedule(
      store,
      schedule(%{schedule_key: "backup-daily", handler_key: "prod_sqlite_backup"})
    )

    setup_run =
      ledger_run(
        "seeded-setup",
        "verified",
        slot(),
        Map.merge(
          %{
            claim_kind: "setup",
            claim_key: "setup:seeded",
            scheduled_for: nil,
            occurrence_number: nil,
            finished_at: at(60)
          },
          artifact("setup")
        )
      )

    :ok = Schedules.put_run!(setup_run)

    assert ScheduleStore.verified_runs(store, "prod_sqlite_backup") ==
             [verified_view("seeded-setup", nil, at(60), "setup")]
  end
end
