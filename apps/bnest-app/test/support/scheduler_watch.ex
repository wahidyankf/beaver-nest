defmodule BnestApp.Test.SchedulerWatch do
  @moduledoc """
  Test-only evidence of what a task did with the Scheduler, for the scenarios that state
  "it starts no scheduler". The task runs under `BnestApp.Test.CallTrace`, which reports the
  calls the BEAM itself saw, so the evidence does not depend on which Scheduler processes the
  test VM happens to hold: the integration VM runs one already and the unit VM none, so a
  comparison of their pids before and after could not fail in either.

  A task has started a Scheduler, or claimed a slot, when its code called an entry point that
  does either:

    * the coordinator's start (`BnestApp.Scheduler.start_link/1`, whose `init/1` follows);
    * the start of the application that supervises the coordinator, directly or through
      `mix app.start` (`:application.start/2`, `ensure_started/2` and `ensure_all_started/2`
      or `/3`, whose first argument names `:bnest_app`, alone or in a list);
    * a claim, through the facade (`claim_due/1`, `claim_setup/3`, `run_now/1`, `execute/2`,
      `reconcile/0`, which asks the coordinator to claim) or the store port.

  `read_ledger?/1` is the positive control: the same trace must show the task reading the
  ledger through the Scheduler, so an empty trace cannot mean that nothing was watched.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Scheduler
  alias BnestApp.Scheduler.Ports.ScheduleStore
  alias BnestApp.Test.CallTrace

  @application :bnest_app
  @facade_claims ~w(start_link init reconcile claim_due claim_setup run_now execute)a
  @port_claims ~w(claim_due claim_setup)a
  @application_starts ~w(start ensure_started ensure_all_started)a

  @watched Enum.flat_map(
             [
               {Scheduler, [:verified_runs | @facade_claims]},
               {ScheduleStore, @port_claims},
               {:application, @application_starts}
             ],
             fn {module, functions} -> Enum.map(functions, &{{module, &1, :_}, []}) end
           )

  @doc "Runs `fun` while tracing the calls that start a Scheduler or claim a slot."
  @spec record((-> result)) :: {result, [CallTrace.event()]} when result: term()
  def record(fun) when is_function(fun, 0), do: CallTrace.record(@watched, fun)

  @doc "The traced calls that started a Scheduler or claimed a slot, as `{module, function}`."
  @spec starts_or_claims([CallTrace.event()]) :: [{module(), atom()}]
  def starts_or_claims(events) do
    for {:call, {module, function, _arity}, _caller, arguments} <- events,
        starts_or_claims?(module, function, arguments),
        do: {module, function}
  end

  @doc "Whether the trace shows the task reading the verified runs through the Scheduler."
  @spec read_ledger?([CallTrace.event()]) :: boolean()
  def read_ledger?(events), do: CallTrace.calls(events, Scheduler, :verified_runs) != []

  defp starts_or_claims?(Scheduler, function, _arguments), do: function in @facade_claims
  defp starts_or_claims?(ScheduleStore, function, _arguments), do: function in @port_claims

  # `Application.ensure_all_started/2` passes the applications as a list, `start/2` as one.
  defp starts_or_claims?(:application, function, [applications | _rest]),
    do: function in @application_starts and @application in List.wrap(applications)

  defp starts_or_claims?(_module, _function, _arguments), do: false
end
