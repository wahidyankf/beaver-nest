defmodule BnestApp.Behaviour.UnitSupport do
  use ExBdd.Hooks

  alias BnestApp.Behaviour.UnitHomePageDriver
  alias BnestApp.Test.InMemory.MessagePublisher
  alias BnestApp.Test.InMemory.RoomStore

  # Every scenario, and every retry of one, starts with a fresh in-memory room store and no
  # recorded publish: the unit layer's Family Chat adapters (config/test.exs).
  before_scenario context do
    RoomStore.install()
    :ok = MessagePublisher.forget_published()
    Map.put(context, :behaviour_driver, UnitHomePageDriver)
  end
end
