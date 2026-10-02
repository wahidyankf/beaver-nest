defmodule BnestApp.Test.SchedulerDispatch do
  @moduledoc """
  Test-only observation of one Scheduler dispatch, shared by the unit and integration
  behaviour drivers: `claim_and_dispatch/2` claims due work through the `BnestApp.Scheduler`
  facade and runs the schedule's claimed run through it, as the coordinator's tick does,
  while `BnestApp.Test.CallTrace` records every registered task's `execute/2`, every call
  into the public services those tasks reach, and every call into the SQLite repository.
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

  @doc "The task that ran, named by its last two module segments, as the scenarios name it."
  @spec ran_task_name(observation()) :: String.t() | nil
  def ran_task_name(seen) do
    case invocations(seen) do
      [{task, _run_id}] -> task |> Module.split() |> Enum.take(-2) |> Enum.join(".")
      _none_or_several -> nil
    end
  end

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
  `{:ok, result}`, and the task's own code made no call into the SQLite repository.
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
          CallTrace.calls_by(seen.events, task, BnestApp.SqliteRepo) == []

      _none_or_several ->
        false
    end
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
      [{{BnestApp.SqliteRepo, :_, :_}, []}]
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
