defmodule BnestApp.Behaviour.OperatorCommandsSteps do
  @moduledoc """
  Bindings for `specs/apps/bnest/app-be/behaviours/operator_commands.feature`.

  Each step delegates to the adapter the layer installed
  (`OperatorCommands.UnitAdapter` for the unit layer,
  `OperatorCommands.IntegrationAdapter` for the integration layer). A
  Given prepares the scenario's isolated state, a When runs the operator
  command, and a Then asserts the recorded evidence, so no step is a
  placeholder or a success literal.
  """

  use ExBdd.StepDefinition

  alias BnestApp.Behaviour.IntegrationHomePageDriver
  alias BnestApp.Behaviour.OperatorCommands.IntegrationAdapter, as: Integration
  alias BnestApp.Behaviour.OperatorCommands.UnitAdapter, as: Unit

  defp adapter(%{behaviour_driver: IntegrationHomePageDriver}), do: Integration
  defp adapter(_), do: Unit

  # The hooks install the web drivers, not the operator adapter: the first
  # operator step of a scenario installs it, later steps reuse the state.
  defp operator(context) do
    if Map.has_key?(context, :operator), do: context, else: adapter(context).install(context)
  end

  # mix bnest.storage.purge_test_data verifies or purges verified legacy test data (BN-CLI-21).

  step("a generation holding verified legacy test data", context) do
    context = operator(context)
    adapter(context).seed_generation(context)
  end

  step("the operator runs purge_test_data with {string}", %{args: [arguments]} = context) do
    context = operator(context)
    adapter(context).run_purge(context, arguments)
  end

  step("the task reports {string}", %{args: [report]} = context) do
    context = operator(context)
    adapter(context).assert_report(context, report)
  end

  step("the legacy test data is {string}", %{args: [state]} = context) do
    context = operator(context)
    adapter(context).assert_legacy_state(context, state)
  end

  # mix bnest.schema.audit prints one pass or fail line per record type (BN-CLI-22).

  step("an auditable default root and an auditable other root", context) do
    context = operator(context)
    adapter(context).seed_audit_roots(context)
  end

  step("the operator runs schema_audit with {string}", %{args: [arguments]} = context) do
    context = operator(context)
    adapter(context).run_audit(context, arguments)
  end

  step("the audit {string}", %{args: [outcome]} = context) do
    context = operator(context)
    adapter(context).assert_audit_outcome(context, outcome)
  end

  # mix bnest.identity.benchmark prints the Argon2id cost and a timing class, never a secret (BN-CLI-23).

  step("a hasher timing of {string}", %{args: [timing]} = context) do
    context = operator(context)
    adapter(context).seed_timing(context, timing)
  end

  step("the operator runs identity_benchmark", context) do
    context = operator(context)
    adapter(context).run_benchmark(context)
  end

  # The storage tasks refuse unknown options with their usage line (BN-CLI-24).

  step("an isolated storage root", context) do
    context = operator(context)
    adapter(context).seed_isolated_root(context)
  end

  step("the operator runs {string} with {string}", %{args: [task, arguments]} = context) do
    context = operator(context)
    adapter(context).run_storage_task(context, task, arguments)
  end

  step("it refuses with {string} and changes nothing", %{args: [usage]} = context) do
    context = operator(context)
    adapter(context).assert_refusal(context, usage)
  end

  # node tools/test-data-cleanup.mjs removes only stale marked test runs and reports the counts (BN-CLI-25).

  step("a test home holding {string}", %{args: [setup]} = context) do
    context = operator(context)
    adapter(context).seed_test_home(context, setup)
  end

  # The bad-arguments outline always starts from the same stale marked run.
  step("a test home holding a stale marked run with a dead owner", context) do
    context = operator(context)
    adapter(context).seed_test_home(context, "a stale marked run with a dead owner")
  end

  step("the operator runs the test-data cleanup", context) do
    context = operator(context)
    adapter(context).run_cleanup(context)
  end

  step("it prints {string}", %{args: [line]} = context) do
    context = operator(context)
    adapter(context).assert_cleanup_line(context, line)
  end

  # Test-data cleanup refuses bad arguments and negative hours (BN-CLI-26).

  step("the operator runs the test-data cleanup with {string}", %{args: [arguments]} = context) do
    context = operator(context)
    adapter(context).run_cleanup_with(context, arguments)
  end

  step(
    "it refuses with {string}, exits non-zero and removes nothing",
    %{args: [refusal]} = context
  ) do
    context = operator(context)
    adapter(context).assert_cleanup_refusal(context, refusal)
  end
end
