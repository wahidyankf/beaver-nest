defmodule BnestApp.Behaviour.IntegrationSupport do
  use ExBdd.Hooks

  before_scenario context do
    Map.put(context, :behaviour_driver, BnestApp.Behaviour.IntegrationHomePageDriver)
  end
end
