defmodule BnestApp.Scheduler.TaskRegistry do
  @moduledoc """
  The tasks configuration registers under each handler key (`config :bnest_app,
  BnestApp.Scheduler, tasks: ...`): the task module, its label, schedule context, typed
  settings key and display timezone. A schedule row stores only the handler key, so renaming
  a task module changes configuration and no stored row.

  It is also the task of the `"fixture"` family handler, which completes its run with an
  empty receipt.
  """

  @behaviour BnestApp.Scheduler.Ports.Task

  alias BnestApp.Scheduler

  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(key), do: Map.fetch(entries(), key)

  @spec entries() :: %{String.t() => map()}
  def entries, do: Scheduler.configuration(:tasks)

  @impl true
  def execute(claim, %DateTime{} = now) do
    receipt = %{
      "artifactBasename" => nil,
      "artifactSha256" => nil,
      "artifactBytes" => nil
    }

    :ok = Scheduler.complete_run(claim.run_id, claim.attempt, receipt, now)
    {:ok, receipt}
  end
end
