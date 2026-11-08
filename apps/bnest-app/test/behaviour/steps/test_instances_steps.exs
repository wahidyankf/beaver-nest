defmodule BnestApp.Behaviour.TestInstancesSteps do
  @moduledoc """
  Bindings for `specs/apps/bnest/app-fe/behaviours/test_instances.feature`, which this harness aggregates
  (ADR 001, section 6). The Given is the shared `an approved admin is logged in` step: for this feature the
  driver hands it to the layer's isolation adapter, which spawns an admin instance and logs the admin in.

  Each step below delegates to the isolation adapter the layer's hook installed (`context.isolation_adapter`).
  The unit adapter answers from the in-memory lifecycle model; the integration adapter answers over the real
  switch, the real endpoints and the production login route. The Then steps read what the When produced and
  never assert a literal.
  """

  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step("the test replaces the current test instance with a fresh one", context,
    do: context.isolation_adapter.replace_instance(context)
  )

  step("Bnest reports the fresh instance's storage generation", context,
    do: assert_reports_fresh_generation(context)
  )

  step("the previous instance's admin account cannot log in", context,
    do: assert_previous_admin_refused(context)
  )

  defp assert_reports_fresh_generation(context) do
    {:ok, fresh} = context.spawn
    {:ok, previous} = context.previous_spawn

    assert fresh.generation != previous.generation
    assert context.isolation_adapter.readiness_generation(context) == fresh.generation
    context
  end

  defp assert_previous_admin_refused(context) do
    assert context.isolation_adapter.login_as_previous_admin(context) == :error
    context
  end
end
