defmodule BnestApp.Scheduler.InMemoryScheduleStoreTest do
  use BnestApp.Test.Contracts.ScheduleStoreContract, async: true

  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore

  defp new_store(_context), do: InMemoryScheduleStore.start()

  defp put_schedule(store, schedule),
    do: :ok = InMemoryScheduleStore.put_schedule(store, schedule)

  test "reads back every run with the columns a stored run carries", %{store: store} do
    put_schedule(store, schedule())
    [claim] = ScheduleStore.claim_due(store, at())

    receipt = %{
      "artifactBasename" => "bnest-in-memory.sqlite3",
      "artifactSha256" => String.duplicate("b", 64),
      "artifactBytes" => 7
    }

    :ok = ScheduleStore.complete(store, claim.run_id, 1, receipt, at(60))

    assert InMemoryScheduleStore.runs(store) == [
             %{
               claim
               | state: "verified",
                 lease_expires_at: nil,
                 artifact_basename: "bnest-in-memory.sqlite3",
                 artifact_sha256: String.duplicate("b", 64),
                 artifact_bytes: 7,
                 finished_at: at(60)
             }
           ]
  end

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

  test "reading verified runs leaves every stored run as it was", %{store: store} do
    put_schedule(
      store,
      schedule(%{schedule_key: "backup-daily", handler_key: "prod_sqlite_backup"})
    )

    verified = Map.merge(%{finished_at: at(60)}, artifact("night"))

    :ok =
      InMemoryScheduleStore.put_run(
        store,
        ledger_run("seeded-verified", "verified", slot(), verified)
      )

    :ok =
      InMemoryScheduleStore.put_run(
        store,
        ledger_run("seeded-failed", "failed", DateTime.add(slot(), -86_400), %{
          failure_category: "io_failed",
          finished_at: at(90)
        })
      )

    stored = InMemoryScheduleStore.runs(store)

    assert [%{run_id: "seeded-verified", slot: slot(), finished_at: at(60)}] ==
             store
             |> ScheduleStore.verified_runs("prod_sqlite_backup")
             |> Enum.map(&Map.take(&1, [:run_id, :slot, :finished_at]))

    assert InMemoryScheduleStore.runs(store) == stored
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

    :ok = InMemoryScheduleStore.put_run(store, setup_run)

    assert ScheduleStore.verified_runs(store, "prod_sqlite_backup") ==
             [verified_view("seeded-setup", nil, at(60), "setup")]
  end

  defp artifact(name) do
    receipt = receipt(name)

    %{
      artifact_basename: receipt["artifactBasename"],
      artifact_sha256: receipt["artifactSha256"],
      artifact_bytes: receipt["artifactBytes"]
    }
  end

  test "the installed store serves new/0 until the test exits" do
    installed = InMemoryScheduleStore.install()

    assert InMemoryScheduleStore.new() == installed
    put_schedule(installed, schedule())
    assert ScheduleStore.get_schedule(InMemoryScheduleStore.new(), "contract-daily") == schedule()
  end
end
