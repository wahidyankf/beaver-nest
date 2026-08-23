defmodule ExBdd.AmbiguousVerificationFixtureSteps do
  use ExBdd.StepDefinition

  step "a valid precondition", context do
    context
  end

  step "a valid action occurs", context do
    context
  end

  step ~r/^a valid action occurs$/, context do
    context
  end

  step "a valid outcome is observed", context do
    context
  end
end
