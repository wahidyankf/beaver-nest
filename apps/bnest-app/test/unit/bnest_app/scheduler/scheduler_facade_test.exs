defmodule BnestApp.Scheduler.FacadeTest do
  # Not async: tests replace the Scheduler's configured tasks and tick handlers, and start
  # the coordinator under its registered name.
  use ExUnit.Case, async: false

  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore

  @now ~U[2026-09-18 20:00:00Z]

  defmodule SkippingTask do
    @moduledoc false
    @behaviour BnestApp.Scheduler.Ports.Task

    @impl true
    def execute(claim, now) do
      :ok = BnestApp.Scheduler.skip_run(claim.run_id, claim.attempt, :destination_changed, now)
      {:skipped, :destination_changed}
    end
  end

  defmodule FailingTask do
    @moduledoc false
    @behaviour BnestApp.Scheduler.Ports.Task

    @impl true
    def execute(_claim, _now), do: {:error, :capacity}
  end

  defmodule RaisingTask do
    @moduledoc false
    @behaviour BnestApp.Scheduler.Ports.Task

    @impl true
    def execute(_claim, _now), do: raise("task crashed")
  end

  defmodule LastingTask do
    @moduledoc false
    @behaviour BnestApp.Scheduler.Ports.Task

    alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore

    # Runs across several lease renewals, then records its result and keeps running a while
    # after its attempt stopped being live, reporting the lease it held before and after.
    @impl true
    def execute(claim, now) do
      leased = lease(claim)
      wait(60)
      renewed = lease(claim)
      receipt = %{"artifactBasename" => nil, "artifactSha256" => nil, "artifactBytes" => nil}
      :ok = BnestApp.Scheduler.complete_run(claim.run_id, claim.attempt, receipt, now)
      wait(30)
      send(self(), {:leases, leased, renewed})
      {:ok, :done}
    end

    defp lease(claim) do
      BnestApp.Scheduler.store()
      |> InMemoryScheduleStore.runs()
      |> Enum.find(&(&1.run_id == claim.run_id))
      |> Map.fetch!(:lease_expires_at)
    end

    defp wait(milliseconds) do
      receive do
      after
        milliseconds -> :ok
      end
    end
  end

  defmodule SlowFailingTask do
    @moduledoc false
    @behaviour BnestApp.Scheduler.Ports.Task

    @impl true
    def execute(_claim, _now) do
      receive do
      after
        30 -> {:error, :capacity}
      end
    end
  end

  defmodule UnavailableStore do
    @moduledoc false
    # A schedule store whose repository has gone away: it still serves the schedule a claim
    # names, then refuses the lease renewal by raising and the failure's bookkeeping by
    # raising or, for the run ID "exiting", by exiting.

    def new, do: %{adapter: __MODULE__}

    def get_schedule(_store, schedule_key), do: %{handler_key: schedule_key}

    def renew_lease(_store, _run_id, _attempt, _now), do: raise("repository unavailable")

    def fail_attempt(_store, "exiting", _attempt, _category, _now),
      do: exit(:repository_unavailable)

    def fail_attempt(_store, _run_id, _attempt, _category, _now),
      do: raise("repository unavailable")
  end

  setup do
    store = InMemoryScheduleStore.install()
    configuration = Application.fetch_env!(:bnest_app, Scheduler)
    on_exit(fn -> Application.put_env(:bnest_app, Scheduler, configuration) end)
    %{store: store, configuration: configuration}
  end

  describe "configuration" do
    test "names the configured store, the registered tasks and the tick handlers", %{
      store: store
    } do
      assert Scheduler.configuration(:schedule_store) == InMemoryScheduleStore
      assert Scheduler.store() == store
      assert %{"prod_sqlite_backup" => _, "fixture" => _} = Scheduler.task_entries()

      assert {:ok, %{context: "family", handler: BnestApp.Scheduler.TaskRegistry}} =
               Scheduler.task_entry("fixture")

      # Backup's task, an adapter of the Backup context the unit layer may not name.
      assert {:ok, backup_task} = Scheduler.registered_handler("prod_sqlite_backup")
      assert ["BnestApp", "Backup" | _adapter] = Module.split(backup_task)

      assert BnestApp.Scheduler.Ports.Task in (backup_task.module_info(:attributes)
                                               |> Keyword.get_values(:behaviour)
                                               |> List.flatten())

      assert Scheduler.registered_handler("missing") == :error
      assert Scheduler.task_entry("missing") == :error
      assert [{_module, _function, _arguments}] = Scheduler.configuration(:tick_handlers)
    end
  end

  describe "claims" do
    test "claims due slots and idempotent setup runs through the configured store" do
      put_schedule("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")

      assert [%{claim_kind: "scheduled", scheduled_for: ~U[2026-09-18 19:00:00Z]} = claim] =
               Scheduler.claim_due(@now)

      assert Scheduler.active_attempt?(claim.run_id, 1, @now)
      assert Scheduler.claim_due(@now) == []

      assert {:ok, setup} = Scheduler.claim_setup("prod-sqlite-backup-daily", "dest-1", @now)
      assert setup.claim_key == "setup:dest-1"
      assert {:ok, ^setup} = Scheduler.claim_setup("prod-sqlite-backup-daily", "dest-1", @now)

      assert Scheduler.claim_setup("prod-sqlite-backup-daily", "../escape", @now) ==
               {:error, :invalid_destination_id}
    end

    test "records a run's completion and skip only for its live attempt" do
      put_schedule("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")
      {:ok, first} = Scheduler.claim_setup("prod-sqlite-backup-daily", "dest-1", @now)
      {:ok, second} = Scheduler.claim_setup("prod-sqlite-backup-daily", "dest-2", @now)

      receipt = %{
        "artifactBasename" => "a.sqlite3",
        "artifactSha256" => "s",
        "artifactBytes" => 1
      }

      assert :ok = Scheduler.complete_run(first.run_id, 1, receipt, @now)
      assert {:error, :stale_attempt} = Scheduler.complete_run(first.run_id, 1, receipt, @now)
      assert :ok = Scheduler.skip_run(second.run_id, 1, :destination_changed, @now)
      refute Scheduler.active_attempt?(second.run_id, 1, @now)

      assert [%{last_run_state: state}] = Scheduler.admin_inventory().admin_system
      assert state in ["verified", "skipped"]
    end
  end

  describe "schedules" do
    test "groups the inventory by context" do
      put_schedule("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")
      put_schedule("family-daily", "fixture", "family")

      assert %{
               family: [%{schedule_key: "family-daily"}],
               admin_system: [%{schedule_key: "prod-sqlite-backup-daily"}]
             } = Scheduler.admin_inventory()

      assert [%{schedule_key: "family-daily", last_run_state: nil}] = Scheduler.family_inventory()
      assert %{schedule_key: "family-daily"} = Scheduler.get_schedule("family-daily")
      assert Scheduler.get_schedule("missing") == nil
    end

    test "applies an operator's daily edit at the revision read" do
      put_schedule("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")
      put_schedule("family-daily", "fixture", "family")
      edit = %{"daily_time_wib" => "02:30", "enabled" => "false", "revision" => "1"}

      assert {:ok, %{daily_at_utc: "19:30", enabled: false, revision: 2}} =
               Scheduler.update_daily("prod-sqlite-backup-daily", edit, @now)

      assert Scheduler.update_daily("prod-sqlite-backup-daily", edit, @now) ==
               {:error, :conflict}

      assert Scheduler.update_daily("family-daily", edit, @now) == {:error, :not_editable}
      assert Scheduler.update_daily("missing", edit, @now) == {:error, :unknown_schedule}

      assert Scheduler.update_daily("prod-sqlite-backup-daily", %{edit | "revision" => "x"}, @now) ==
               {:error, :invalid_revision}
    end

    test "converges and activates a pristine schedule once" do
      put_schedule("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")

      put_schedule(
        "family-chat-push-retention-daily",
        "family_chat_push_retention",
        "admin_system",
        enabled: false
      )

      assert {:ok, %{daily_at_utc: "18:00", revision: 2} = converged} =
               Scheduler.converge_backup_time!("prod-sqlite-backup-daily", "18:00")

      assert {:ok, ^converged} =
               Scheduler.converge_backup_time!("prod-sqlite-backup-daily", "17:00")

      assert :ok = Scheduler.activate_if_pristine!("family-chat-push-retention-daily", @now)

      assert %{enabled: true, revision: 2} =
               Scheduler.get_schedule("family-chat-push-retention-daily")
    end
  end

  describe "running a claim" do
    test "runs the registered task, which records its own result" do
      put_schedule("family-daily", "fixture", "family")
      [claim] = Scheduler.claim_due(@now)

      assert :ok = Scheduler.execute(claim, @now)
      assert [%{last_run_state: "verified"}] = Scheduler.family_inventory()
    end

    test "records a failed attempt for a failing, raising, or unregistered task" do
      put_tasks(%{"failing" => FailingTask, "raising" => RaisingTask})
      put_schedule("failing-daily", "failing", "family")
      put_schedule("raising-daily", "raising", "family")
      put_schedule("unknown-daily", "unregistered", "family")

      for claim <- Scheduler.claim_due(@now), do: assert(:ok = Scheduler.execute(claim, @now))

      categories =
        for run <- InMemoryScheduleStore.runs(Scheduler.store()),
            into: %{},
            do: {run.schedule_key, {run.state, run.failure_category}}

      assert categories == %{
               "failing-daily" => {"retryable", "capacity"},
               "raising-daily" => {"retryable", "handler_failed"},
               "unknown-daily" => {"retryable", "unknown_handler"}
             }
    end

    test "a skipping task records its skip" do
      put_tasks(%{"skipping" => SkippingTask})
      put_schedule("skipping-daily", "skipping", "family")
      [claim] = Scheduler.claim_due(@now)

      assert :ok = Scheduler.execute(claim, @now)
      assert [%{last_run_state: "skipped"}] = Scheduler.family_inventory()
    end

    test "runs a claim now, under the task supervisor when it runs" do
      put_schedule("family-daily", "fixture", "family")
      {:ok, first} = Scheduler.claim_setup("family-daily", "dest-1", @now)
      {:ok, second} = Scheduler.claim_setup("family-daily", "dest-2", @now)

      assert {:ok, _task} = Scheduler.run_now(first)
      start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})
      assert {:ok, _task} = Scheduler.run_now(second)

      assert eventually(fn ->
               Enum.all?(InMemoryScheduleStore.runs(Scheduler.store()), &(&1.state == "verified"))
             end)
    end
  end

  describe "a running task's lease" do
    test "is renewed while its attempt runs and no longer once the attempt stops being live" do
      put_configuration(:lease_renewal_interval_ms, 5)
      put_tasks(%{"lasting" => LastingTask})
      put_schedule("lasting-daily", "lasting", "family")
      [claim] = Scheduler.claim_due(@now)

      assert :ok = Scheduler.execute(claim, @now)
      assert_received {:leases, leased, renewed}
      assert DateTime.compare(renewed, leased) == :gt
      assert [%{last_run_state: "verified"}] = Scheduler.family_inventory()
    end

    test "ends the run quietly when the store can no longer renew it or record its failure" do
      put_configuration(:lease_renewal_interval_ms, 5)
      put_tasks(%{"slow-failing" => SlowFailingTask})
      put_configuration(:schedule_store, UnavailableStore)

      for run_id <- ["raising", "exiting"] do
        claim = %{run_id: run_id, attempt: 1, schedule_key: "slow-failing"}
        assert :ok = Scheduler.execute(claim, @now)
      end
    end
  end

  describe "the coordinator" do
    test "claims due work on boot and on reconcile, and runs the tick handlers" do
      test = self()
      put_tick_handlers([{Kernel, :send, [test, :ticked]}])
      put_schedule("family-daily", "fixture", "family")
      refute Scheduler.ready?()

      start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})
      start_supervised!({Scheduler, clock: fn -> @now end, automatic?: false})
      assert :ok = Scheduler.reconcile()
      assert Scheduler.ready?()

      assert_receive :ticked
      refute_received :ticked

      assert eventually(fn ->
               Scheduler.family_inventory() |> hd() |> Map.get(:last_run_state) == "verified"
             end)
    end

    test "keeps ticking while its store or tick handlers are not ready" do
      start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})
      start_supervised!({Scheduler, clock: fn -> @now end})

      Application.put_env(
        :bnest_app,
        Scheduler,
        Keyword.delete(Application.fetch_env!(:bnest_app, Scheduler), :tick_handlers)
      )

      assert :ok = Scheduler.reconcile()

      stop_supervised!(InMemoryScheduleStore)
      assert :ok = Scheduler.reconcile()
      assert Scheduler.ready?()
    end
  end

  defp put_schedule(key, handler_key, context, fields \\ []) do
    :ok =
      InMemoryScheduleStore.put_daily_schedule(
        Scheduler.store(),
        key,
        handler_key,
        context,
        @now,
        Map.new(fields)
      )
  end

  defp put_tasks(tasks) do
    entries =
      Map.new(tasks, fn {key, handler} ->
        {key,
         %{label: key, context: "family", handler: handler, settings_key: nil, timezone: "UTC"}}
      end)

    configuration = Application.fetch_env!(:bnest_app, Scheduler)
    tasks = Map.merge(Keyword.fetch!(configuration, :tasks), entries)
    Application.put_env(:bnest_app, Scheduler, Keyword.put(configuration, :tasks, tasks))
  end

  defp put_tick_handlers(handlers), do: put_configuration(:tick_handlers, handlers)

  defp put_configuration(key, value) do
    configuration = Application.fetch_env!(:bnest_app, Scheduler)
    Application.put_env(:bnest_app, Scheduler, Keyword.put(configuration, key, value))
  end

  defp eventually(check, attempts \\ 200) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        receive do
        after
          10 -> eventually(check, attempts - 1)
        end
    end
  end
end
