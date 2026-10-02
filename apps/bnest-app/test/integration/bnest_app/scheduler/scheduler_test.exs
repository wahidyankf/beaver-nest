defmodule BnestApp.SchedulerTest do
  use ExUnit.Case, async: false

  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler
  alias BnestApp.Scheduler.Ports.ScheduleStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Test.Seeds.Schedules
  alias BnestApp.TestRuntimeRoot

  @now ~U[2026-08-30 20:00:00Z]

  setup do
    runtime = TestRuntimeRoot.create!("scheduler")
    :ok = SqliteCoordinator.ensure_started!(Path.join(runtime.sqlite_path, "bnest.sqlite3"))
    :ok = PersistentSchedules.apply_and_verify!(@now)

    on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    :ok
  end

  test "two coordinators claim one latest missed slot and advance future" do
    claims =
      1..2
      |> Task.async_stream(fn _ -> Scheduler.claim_due(@now) end, max_concurrency: 2)
      |> Enum.flat_map(fn {:ok, rows} -> rows end)

    assert [%{claim_kind: "scheduled", scheduled_for: ~U[2026-08-30 19:00:00Z]}] = claims

    assert Scheduler.get_schedule("prod-sqlite-backup-daily").next_run_at ==
             ~U[2026-08-31 19:00:00Z]
  end

  test "setup claims are idempotent per destination" do
    assert {:ok, first} =
             Scheduler.claim_setup("prod-sqlite-backup-daily", "destination-safe", @now)

    assert {:ok, same} =
             Scheduler.claim_setup("prod-sqlite-backup-daily", "destination-safe", @now)

    assert first.run_id == same.run_id
    assert Schedules.run_count() == 1
  end

  test "retry preserves occurrence and stops after three attempts" do
    [claim] = Scheduler.claim_due(@now)

    assert {:retryable, attempt_2} =
             ScheduleStore.fail_attempt(
               Scheduler.store(),
               claim.run_id,
               claim.attempt,
               :capacity,
               @now
             )

    assert attempt_2.occurrence_number == claim.occurrence_number
    attempt_2_at = DateTime.add(@now, 5 * 60)
    retried_2 = Enum.find(Scheduler.claim_due(attempt_2_at), &(&1.run_id == claim.run_id))
    assert retried_2.attempt == 2

    assert {:retryable, attempt_3} =
             ScheduleStore.fail_attempt(
               Scheduler.store(),
               claim.run_id,
               2,
               :capacity,
               attempt_2_at
             )

    attempt_3_at = DateTime.add(attempt_2_at, 30 * 60)
    retried_3 = Enum.find(Scheduler.claim_due(attempt_3_at), &(&1.run_id == claim.run_id))
    assert retried_3.attempt == 3
    assert attempt_3.occurrence_number == claim.occurrence_number

    assert {:failed, final} =
             ScheduleStore.fail_attempt(
               Scheduler.store(),
               claim.run_id,
               3,
               :capacity,
               attempt_3_at
             )

    assert final.attempt == 3
  end

  test "a running attempt renews its lease and rejects stale fencing tokens" do
    [claim] = Scheduler.claim_due(@now)
    renewed_at = DateTime.add(@now, 60)

    assert :ok = ScheduleStore.renew_lease(Scheduler.store(), claim.run_id, 1, renewed_at)
    assert Scheduler.active_attempt?(claim.run_id, 1, DateTime.add(@now, 15 * 60))
    refute Scheduler.active_attempt?(claim.run_id, 1, DateTime.add(renewed_at, 15 * 60))

    assert {:retryable, _retry} =
             ScheduleStore.fail_attempt(Scheduler.store(), claim.run_id, 1, :capacity, renewed_at)

    assert {:error, :stale_attempt} =
             ScheduleStore.renew_lease(Scheduler.store(), claim.run_id, 1, renewed_at)

    refute Scheduler.active_attempt?(claim.run_id, 1, renewed_at)
  end

  test "admin and family reads enforce context boundaries" do
    :ok = Schedules.put_test_schedule("family-daily", "family", "fixture", @now)
    assert %{family: [_], admin_system: [_]} = Scheduler.admin_inventory()
    assert [%{schedule_context: "family"}] = Scheduler.family_inventory()
    assert Enum.all?(Scheduler.admin_inventory().admin_system, &Map.has_key?(&1, :last_run_state))
  end

  test "occurrence expiry dispatches the final claim and rejects later slots" do
    :ok = Schedules.put_test_schedule("twice", "family", "fixture", @now, max_occurrences: 1)
    claims = Scheduler.claim_due(@now)
    assert Enum.any?(claims, &(&1.schedule_key == "twice"))
    assert Scheduler.get_schedule("twice").expired_at != nil

    refute Enum.any?(Scheduler.claim_due(DateTime.add(@now, 86_400)), fn claim ->
             claim.schedule_key == "twice" and claim.occurrence_number > 1
           end)
  end
end
