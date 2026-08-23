defmodule SimpleSteps do
  use ExBdd.StepDefinition

  step "a simple step", context do
    Map.put(context, :simple, true)
  end
end
