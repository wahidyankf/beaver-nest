defmodule BnestApp.Scheduler.WatchTest do
  # Not async: tracing is global to the VM while a function runs, and the facade reaches the
  # in-memory schedule store the test installs under its module name.
  use ExUnit.Case, async: false

  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestApp.Test.SchedulerWatch

  @now ~U[2026-09-18 20:00:00Z]
  @handler "prod_sqlite_backup"

  setup do
    InMemoryScheduleStore.install()
    :ok
  end

  describe "a read of the ledger through the Scheduler" do
    test "is seen as a read and as neither a start nor a claim" do
      {_runs, events} = SchedulerWatch.record(fn -> Scheduler.verified_runs(@handler) end)

      assert SchedulerWatch.read_ledger?(events)
      assert SchedulerWatch.starts_or_claims(events) == []
    end

    test "is not seen when the function reads nothing, so an empty trace proves nothing" do
      {_result, events} = SchedulerWatch.record(fn -> :nothing end)

      refute SchedulerWatch.read_ledger?(events)
    end
  end

  describe "the entry points that claim" do
    test "are reported through the facade and through the store port" do
      {_claimed, events} = SchedulerWatch.record(fn -> Scheduler.claim_due(@now) end)

      assert SchedulerWatch.starts_or_claims(events) ==
               [
                 {Scheduler, :claim_due},
                 {BnestApp.Scheduler.Ports.ScheduleStore, :claim_due}
               ]
    end

    # The schedule is unknown to the store, which raises: the call was made all the same.
    test "are reported for a setup claim, whatever the store answers" do
      {_result, events} =
        SchedulerWatch.record(fn ->
          try do
            Scheduler.claim_setup("prod-sqlite-backup-daily", String.duplicate("A", 22), @now)
          rescue
            RuntimeError -> :unknown_schedule
          end
        end)

      assert {Scheduler, :claim_setup} in SchedulerWatch.starts_or_claims(events)
    end
  end

  describe "the start of the application that supervises the coordinator" do
    test "is reported when the first argument names it, alone or in a list" do
      events =
        for applications <- [:bnest_app, [:bnest_app], [:logger, :bnest_app]],
            function <- [:start, :ensure_started, :ensure_all_started] do
          {:call, {:application, function, 2}, __MODULE__, [applications, :temporary]}
        end

      assert length(SchedulerWatch.starts_or_claims(events)) == length(events)
    end

    test "is not reported for another application, whatever Elixir's call looks like" do
      {_result, events} =
        SchedulerWatch.record(fn -> Application.ensure_all_started(:logger) end)

      started =
        for {:call, {:application, :ensure_all_started, _arity}, _caller, [first | _]} <- events,
            do: first

      assert started == [[:logger]]
      assert SchedulerWatch.starts_or_claims(events) == []
    end
  end
end
