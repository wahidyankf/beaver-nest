defmodule BnestApp.Scheduler.Adapters do
  @moduledoc """
  The Scheduler's outbound adapters: the schedule store over the shared SQLite database.
  Only configuration names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.Scheduler, BnestApp.SqliteRepo],
    exports: :all
end
