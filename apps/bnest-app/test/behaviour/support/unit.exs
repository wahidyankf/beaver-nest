defmodule BnestApp.Behaviour.UnitSupport do
  use ExBdd.Hooks

  before_scenario context do
    Map.put(context, :behaviour_driver, BnestApp.Behaviour.UnitHomePageDriver)
  end
end
