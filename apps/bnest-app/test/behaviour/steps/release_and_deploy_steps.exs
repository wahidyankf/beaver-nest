defmodule BnestApp.Behaviour.ReleaseAndDeploySteps do
  @moduledoc """
  Bindings for `specs/apps/bnest/app-be/behaviours/release_and_deploy.feature`.

  Each step delegates to the adapter the layer installed
  (`ReleaseAndDeploy.UnitAdapter` for the unit layer,
  `ReleaseAndDeploy.IntegrationAdapter` for the integration layer). A Given
  or When records what it observed, and a Then asserts that recorded
  evidence, so no step is a placeholder or a success literal.
  """

  use ExBdd.StepDefinition

  alias BnestApp.Behaviour.IntegrationHomePageDriver
  alias BnestApp.Behaviour.ReleaseAndDeploy.IntegrationAdapter, as: Integration
  alias BnestApp.Behaviour.ReleaseAndDeploy.UnitAdapter, as: Unit

  defp adapter(%{behaviour_driver: IntegrationHomePageDriver}), do: Integration
  defp adapter(_), do: Unit

  # The hooks install the web drivers, not the commands adapter: the first
  # commands step of a scenario installs it, later steps reuse the state.
  defp commands(context) do
    if Map.has_key?(context, :commands), do: context, else: adapter(context).install(context)
  end

  # release:run builds an immutable artifact, promotes it, and prints one
  # JSON result (BN-REL-01, BN-DOC-04).

  step("a release host records its calls", context) do
    context = commands(context)
    adapter(context).record_host(context)
  end

  step("release:run runs for the revision", context) do
    context = commands(context)
    adapter(context).run_release(context)
  end

  step("the recorded call order is {string}", %{args: [order]} = context) do
    context = commands(context)
    adapter(context).assert_call_order(context, order)
  end

  step("the printed line is one JSON result with outcome {string}", %{args: [outcome]} = context) do
    context = commands(context)
    adapter(context).assert_json_result(context, outcome)
  end

  # release exits 0 for passed, queued, and deferred and 1 for every other
  # outcome (BN-REL-02).

  step("a release host throws {string} with outcome {string}", %{args: [category, outcome]} = context) do
    context = commands(context)
    adapter(context).throwing_host(context, category, outcome)
  end

  step("the printed JSON carries outcome {string} and the exit status is {int}", %{args: [outcome, status]} = context) do
    context = commands(context)
    adapter(context).assert_exit_status(context, outcome, status)
  end

  # release --mode experience re-promotes the routed artifact with the family
  # chat flags on (BN-REL-03).

  step("an experience host records its calls", context) do
    context = commands(context)
    adapter(context).experience_host(context)
  end

  step("release --mode experience runs for the routed revision", context) do
    context = commands(context)
    adapter(context).run_experience_release(context)
  end

  step("it never builds, migrates, or discards an artifact and prepares with the family chat flags on", context) do
    context = commands(context)
    adapter(context).assert_experience_candidate(context)
  end

  step("its only gate is the experience release E2E", context) do
    context = commands(context)
    adapter(context).assert_only_experience_gate(context)
  end

  # An unknown release mode stops with a configuration error (BN-REL-04).

  step("the release arguments are {string}", %{args: [args]} = context) do
    context = commands(context)
    adapter(context).release_arguments(context, args)
  end

  step("the mode is parsed", context) do
    context = commands(context)
    adapter(context).parse_mode(context)
  end

  step("it throws configuration {string} before any host exists", %{args: [message]} = context) do
    context = commands(context)
    adapter(context).assert_mode_refusal(context, "configuration", message)
  end

  # release:build, release:migrate, and release:converge each run one step
  # against the immutable artifact (BN-REL-06).

  step("the release artifact for {string} is {string} and the worktree is {string}", %{args: [revision, artifact, worktree]} = context) do
    context = commands(context)
    adapter(context).artifact_state(context, revision, artifact, worktree)
  end

  step("the {string} command runs with its doubles", %{args: [command]} = context) do
    context = commands(context)
    adapter(context).run_artifact_command(context, command)
  end

  step("it records {string} and prints {string}", %{args: [calls, prints]} = context) do
    context = commands(context)
    adapter(context).assert_artifact_calls(context, calls, prints)
  end

  step("a failure reports {string}", %{args: [failure]} = context) do
    context = commands(context)
    adapter(context).assert_artifact_failure(context, failure)
  end

  # deploy:prepare and deploy:promote take a blue or green slot (BN-REL-07).

  step("the deploy command {string} is invoked with {string} against {string}", %{args: [command, args, state]} = context) do
    context = commands(context)
    adapter(context).slot_arguments(context, command, args, state)
  end

  step("the slot command runs with its doubles", context) do
    context = commands(context)
    adapter(context).run_slot_command(context)
  end

  step("it records {string} and refuses {string}", %{args: [calls, refusal]} = context) do
    context = commands(context)
    adapter(context).assert_slot_calls(context, calls, refusal)
  end

  # Promotion waits up to 60 seconds for the slot to report its revision
  # (BN-REL-08).

  step("the {string} slot reports {string}", %{args: [slot, report]} = context) do
    context = commands(context)
    adapter(context).readiness_report(context, slot, report)
  end

  step("the readiness wait runs with its doubles", context) do
    context = commands(context)
    adapter(context).run_readiness(context)
  end

  step("it ends with {string}", %{args: [ending]} = context) do
    context = commands(context)
    adapter(context).assert_wait(context, ending)
  end

  # deploy:rollback returns traffic to the previous slot or refuses (BN-REL-09).

  step("the previous slot is {string}", %{args: [previous]} = context) do
    context = commands(context)
    adapter(context).previous_slot(context, previous)
  end

  step("rollback runs with its doubles", context) do
    context = commands(context)
    adapter(context).run_rollback(context)
  end

  step("it activates {string} or refuses {string}", %{args: [active, refusal]} = context) do
    context = commands(context)
    adapter(context).assert_rollback(context, active, refusal)
  end

  # deploy:retire stops a slot through the platform service adapter and
  # refuses the active slot (BN-REL-10).

  step("the platform is {string} and the active slot is {string}", %{args: [platform, active]} = context) do
    context = commands(context)
    adapter(context).retire_context(context, platform, active)
  end

  step("retire runs for {string} with its doubles", %{args: [slot]} = context) do
    context = commands(context)
    adapter(context).run_retire(context, slot)
  end

  step("it stops {string} or refuses {string}", %{args: [stopped, refusal]} = context) do
    context = commands(context)
    adapter(context).assert_retire(context, stopped, refusal)
  end

  # A missing revision or an unknown deployment command is refused (BN-REL-11).

  step("the deployment arguments are {string}", %{args: [args]} = context) do
    context = commands(context)
    adapter(context).deployment_arguments(context, args)
  end

  step("the dispatcher runs with its doubles", context) do
    context = commands(context)
    adapter(context).run_dispatcher(context)
  end

  step("it refuses {string} on stderr with exit 1 and no side effect", %{args: [message]} = context) do
    context = commands(context)
    adapter(context).assert_dispatcher_refusal(context, message)
  end

  # A deploy root inside the repository or a production origin that is not a
  # bare HTTPS origin is refused (BN-REL-12).

  step("the deploy root is {string} and the production origin is {string}", %{args: [root, origin]} = context) do
    context = commands(context)
    adapter(context).config_values(context, root, origin)
  end

  step("the deployment configuration is checked", context) do
    context = commands(context)
    adapter(context).check_configuration(context)
  end

  step("it refuses {string}", %{args: [message]} = context) do
    context = commands(context)
    adapter(context).assert_config_refusal(context, message)
  end

  step("release:run reports outcome {string} with errorCategory {string}", %{args: ["failed", "configuration"]} = context) do
    context = commands(context)
    adapter(context).assert_release_configuration(context)
  end

  # The release builds in a detached worktree and removes it afterwards,
  # also when the build fails (BN-REL-13).

  step("a release build records its run calls", context) do
    context = commands(context)
    adapter(context).record_build_runs(context)
  end

  step("the build succeeds and when the build throws", context) do
    context = commands(context)
    adapter(context).run_builds(context)
  end

  step("both runs add and remove the same detached worktree and the checkout is unchanged", context) do
    context = commands(context)
    adapter(context).assert_worktrees(context)
  end

  # The release tool picks the service manager for the platform and stops on
  # any other platform (BN-REL-15).

  step("the platform is {string}", %{args: [platform]} = context) do
    context = commands(context)
    adapter(context).platform_is(context, platform)
  end

  step("the service adapter is picked", context) do
    context = commands(context)
    adapter(context).pick_adapter(context)
  end

  step("it uses {string} or stops with {string}", %{args: [adapter, message]} = context) do
    context = commands(context)
    adapter(context).assert_adapter(context, adapter, message)
  end
end
