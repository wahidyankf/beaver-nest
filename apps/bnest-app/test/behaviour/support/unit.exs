defmodule BnestApp.Behaviour.UnitSupport do
  use ExBdd.Hooks

  alias BnestApp.Behaviour.UnitHomePageDriver
  alias BnestApp.Test.InMemory.MessagePublisher
  alias BnestApp.Test.InMemory.PushSender
  alias BnestApp.Test.InMemory.RoomStore
  alias BnestApp.Test.InMemory.ScheduleStore

  # Every scenario, and every retry of one, starts with a fresh in-memory room store (which
  # also holds Push Notifications' subscriptions and deliveries), a fresh in-memory schedule
  # store, no recorded publish and no recorded push request: the unit layer's Family Chat,
  # Push Notifications and Scheduler adapters (config/test.exs).
  before_scenario context do
    RoomStore.install()
    ScheduleStore.install()
    :ok = MessagePublisher.forget_published()
    :ok = PushSender.forget_sent()
    Map.put(context, :behaviour_driver, UnitHomePageDriver)
  end
end
