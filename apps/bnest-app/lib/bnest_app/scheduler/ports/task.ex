defmodule BnestApp.Scheduler.Ports.Task do
  @moduledoc """
  A unit of scheduled work. Configuration registers each task under the handler key its
  schedules name (`config :bnest_app, BnestApp.Scheduler, tasks: ...`), and the Scheduler
  runs the task registered for a claimed run's schedule. Task adapters live in the context
  that owns the work and reach it only through that context's facade.

  `execute/2` runs one claimed attempt at `now`. The claim is the run as
  `BnestApp.Scheduler.Ports.ScheduleStore` claimed it. A task that finishes its run records
  the result itself through the Scheduler facade (`complete_run/4`, `skip_run/4`), then
  returns `{:ok, result}` or `{:skipped, category}`. `{:error, category}` makes the Scheduler
  record a failed attempt under that category, which it retries while attempts remain.
  """

  @callback execute(claim :: map(), now :: DateTime.t()) ::
              {:ok, map()} | {:skipped, atom()} | {:error, atom()}
end
