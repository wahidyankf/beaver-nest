defmodule BnestApp.Scheduler.Ports do
  @moduledoc """
  The behaviours the Scheduler needs from the outside world: the store of schedules and
  their runs, which adapters under `BnestApp.Scheduler.Adapters` implement, and the task
  every unit of scheduled work implements. Configuration chooses both.
  """

  use Boundary, type: :strict, deps: [BnestApp.Scheduler.Domain], exports: :all
end
