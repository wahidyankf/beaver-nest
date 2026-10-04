defmodule BnestApp.Test.UnreadableLedger do
  @moduledoc """
  Test-only Scheduler `:schedule_store` adapter for a ledger that cannot be read: the store
  cannot be opened, so every Scheduler facade call raises, whichever layer's store the run
  would otherwise use. It stands for an unreadable or unavailable ledger database, the case
  the reconcile task must report as "could not be checked" instead of crashing.

  `install!/0` makes it the configured store until the calling test exits. It declares no
  `ScheduleStore` behaviour on purpose: it implements `new/0` only, because the Scheduler
  facade reaches a store through `new/0` first and so never gets past it.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Scheduler

  @spec install!() :: :ok
  def install! do
    previous = Application.fetch_env!(:bnest_app, Scheduler)
    Application.put_env(:bnest_app, Scheduler, Keyword.put(previous, :schedule_store, __MODULE__))

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:bnest_app, Scheduler, previous) end)
  end

  @doc "Raises: the ledger store cannot be opened."
  @spec new() :: no_return()
  def new, do: raise(RuntimeError, "the synthetic ledger cannot be read")
end
