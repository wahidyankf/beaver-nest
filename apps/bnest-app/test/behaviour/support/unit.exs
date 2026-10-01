defmodule BnestApp.Behaviour.UnitSupport do
  use ExBdd.Hooks

  alias BnestApp.Behaviour.UnitHomePageDriver
  alias BnestApp.Test.InMemory.MessagePublisher
  alias BnestApp.Test.InMemory.PushSender
  alias BnestApp.Test.InMemory.RoomStore

  # Every scenario, and every retry of one, starts with a fresh in-memory room store (which
  # also holds Push Notifications' subscriptions and deliveries), no recorded publish and no
  # recorded push request: the unit layer's Family Chat and Push Notifications adapters
  # (config/test.exs).
  before_scenario context do
    RoomStore.install()
    :ok = MessagePublisher.forget_published()
    :ok = PushSender.forget_sent()
    Map.put(context, :behaviour_driver, UnitHomePageDriver)
  end
end
