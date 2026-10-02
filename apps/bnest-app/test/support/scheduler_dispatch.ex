defmodule BnestApp.Test.SchedulerDispatch do
  @moduledoc """
  Test-only observation of one Scheduler dispatch, shared by the unit and integration
  behaviour drivers: `claim_and_dispatch/2` claims due work through the `BnestApp.Scheduler`
  facade and runs the schedule's claimed run through it, as the coordinator's tick does,
  while `BnestApp.Test.CallTrace` records every registered task's `execute/2`, every call
  into the public services those tasks reach, every run they record complete through the
  facade's `complete_run/4`, and every call into the SQLite repository.
  The predicates then read what ran from that record, never from the task registry alone.
  `coordinate/2` observes the coordinator itself claiming and running due work instead.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Scheduler
  alias BnestApp.Test.CallTrace

  # The public services the registered tasks delegate to.
  @services [BnestApp.Backup, BnestApp.PushNotifications]

  @type observation :: %{
          claimed: map() | nil,
          schedule_key: String.t(),
          tasks: [module()],
          registered: {:ok, module()} | :error,
          events: [CallTrace.event()]
        }

  @doc """
  Claims due work at `now` and runs the claimed run of `schedule_key` through the Scheduler,
  observing what that run called. The other claims are left claimed, unrun.
  """
  @spec claim_and_dispatch(String.t(), DateTime.t()) :: observation()
  def claim_and_dispatch(schedule_key, %DateTime{} = now) do
    claimed = now |> Scheduler.claim_due() |> Enum.find(&(&1.schedule_key == schedule_key))
    tasks = registered_tasks()

    {_result, events} =
      if claimed,
        do: CallTrace.record(watched(tasks), fn -> Scheduler.execute(claimed, now) end),
        else: {nil, []}

    %{
      claimed: claimed,
      schedule_key: schedule_key,
      tasks: tasks,
      registered: registered_task(schedule_key),
      events: events
    }
  end

  @doc """
  Runs `reconcile`, which has the Scheduler's coordinator claim due work and start each
  claimed run under the shared `BnestApp.Scheduler.Tasks` supervisor, waits until every
  process that supervisor started has finished, and observes what they ran. Only that
  supervisor's processes are traced, so every task observed ran under it, never in the
  caller. The observation names no claim: the coordinator made it.
  """
  @spec coordinate(String.t(), (-> term())) :: observation()
  def coordinate(schedule_key, reconcile) when is_function(reconcile, 0) do
    supervisor = Process.whereis(BnestApp.Scheduler.Tasks)
    tasks = registered_tasks()

    {_result, events} =
      CallTrace.record(
        watched(tasks),
        fn ->
          reconcile.()
          await_children(supervisor)
        end,
        processes: [supervisor]
      )

    %{
      claimed: nil,
      schedule_key: schedule_key,
      tasks: tasks,
      registered: registered_task(schedule_key),
      events: events
    }
  end

  @doc """
  What the task returned, when exactly one task ran, once, under the coordinator's
  supervisor, for a run of the observed schedule, and it is the task the configuration
  registers for that schedule; otherwise nil.
  """
  @spec coordinated_result(observation()) :: term()
  def coordinated_result(%{schedule_key: key, registered: {:ok, task}} = seen) do
    claims =
      for task <- seen.tasks,
          {_caller, [claim, _now]} <- CallTrace.calls(seen.events, task, :execute),
          do: {task, claim}

    case {claims, CallTrace.results(seen.events, task, :execute)} do
      {[{^task, %{schedule_key: ^key}}], [result]} -> result
      _none_several_or_other -> nil
    end
  end

  def coordinated_result(_seen), do: nil

  @doc """
  Whether exactly one task ran, once, for the claimed run: the task the configuration
  registers under the schedule's handler key, which declares the Scheduler's task behaviour.
  """
  @spec only_registered_task_ran?(observation()) :: boolean()
  def only_registered_task_ran?(%{claimed: %{run_id: run_id}, registered: {:ok, task}} = seen) do
    behaviours = task.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
    invocations(seen) == [{task, run_id}] and BnestApp.Scheduler.Ports.Task in behaviours
  end

  def only_registered_task_ran?(_seen), do: false

  @doc """
  The task that ran, as the scenarios name it: by the name a scenario gave it before it
  moved into its context's adapters, otherwise by its last two module segments.
  """
  @spec ran_task_name(observation()) :: String.t() | nil
  def ran_task_name(seen) do
    case invocations(seen) do
      [{task, _run_id}] -> scenario_name(task)
      _none_or_several -> nil
    end
  end

  # `family_chat_operations.feature` names Backup's task "Backup.Run", the module it ran
  # as before it became `Backup.Adapters.ScheduledBackupTask`.
  defp scenario_name(BnestApp.Backup.Adapters.ScheduledBackupTask), do: "Backup.Run"
  defp scenario_name(task), do: task |> Module.split() |> Enum.take(-2) |> Enum.join(".")

  @doc """
  Whether the task that ran called `service`'s public `function` itself.
  """
  @spec ran_task_called?(observation(), module(), atom()) :: boolean()
  def ran_task_called?(seen, service, function) do
    case invocations(seen) do
      [{task, _run_id}] ->
        seen.events |> CallTrace.calls_by(task, service) |> Enum.any?(&match?({^function, _}, &1))

      _none_or_several ->
        false
    end
  end

  @doc """
  Whether the task that ran delegated to `service`: it called the service's public functions,
  each of which returned the service's `{:ok, result}`, the task itself returned
  `{:ok, result}`, and the task's own code made no call into the SQLite repository. As the
  Scheduler's task behaviour requires, the task also recorded its claimed run complete
  through the Scheduler facade, which the schedule store accepted.
  """
  @spec delegated_without_sql?(observation(), module()) :: boolean()
  def delegated_without_sql?(seen, service) do
    case invocations(seen) do
      [{task, _run_id}] ->
        service_calls = CallTrace.calls_by(seen.events, task, service)

        service_calls != [] and
          Enum.all?(service_calls, fn {function, _arity} ->
            results = CallTrace.results(seen.events, service, function)
            results != [] and Enum.all?(results, &match?({:ok, _effect}, &1))
          end) and
          Enum.all?(CallTrace.results(seen.events, task, :execute), &match?({:ok, _}, &1)) and
          CallTrace.calls_by(seen.events, task, BnestApp.SqliteRepo) == [] and
          completed_its_run?(seen, task)

      _none_or_several ->
        false
    end
  end

  # The task's own `Scheduler.complete_run/4` calls name its claimed run and attempt, and
  # each returned `:ok`: the store recorded that attempt verified.
  defp completed_its_run?(%{claimed: %{run_id: run_id, attempt: attempt}} = seen, task) do
    completions =
      for {^task, [^run_id, ^attempt, _receipt, _now]} <-
            CallTrace.calls(seen.events, Scheduler, :complete_run),
          do: :completed

    results = CallTrace.results(seen.events, Scheduler, :complete_run)

    completions != [] and length(results) == length(completions) and
      Enum.all?(results, &(&1 == :ok))
  end

  # Each registered task's `execute/2` call, with the run it was given.
  defp invocations(seen) do
    for task <- seen.tasks,
        {_caller, [claim, _now]} <- CallTrace.calls(seen.events, task, :execute),
        do: {task, claim.run_id}
  end

  defp registered_tasks,
    do: Scheduler.task_entries() |> Map.values() |> Enum.map(& &1.handler) |> Enum.uniq()

  defp watched(tasks) do
    Enum.map(tasks, &{{&1, :execute, 2}, results: true}) ++
      Enum.map(@services, &{{&1, :_, :_}, results: true}) ++
      [{{Scheduler, :complete_run, 4}, results: true}, {{BnestApp.SqliteRepo, :_, :_}, []}]
  end

  # Every process the supervisor runs ends: a claimed run when its task returns.
  defp await_children(supervisor) do
    supervisor
    |> Task.Supervisor.children()
    |> Enum.map(&Process.monitor/1)
    |> Enum.each(fn monitor ->
      receive do
        {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
      after
        30_000 -> raise "a run the Scheduler started did not finish"
      end
    end)
  end

  defp registered_task(schedule_key) do
    case Scheduler.get_schedule(schedule_key) do
      %{handler_key: handler_key} -> Scheduler.registered_handler(handler_key)
      nil -> :error
    end
  end
end
