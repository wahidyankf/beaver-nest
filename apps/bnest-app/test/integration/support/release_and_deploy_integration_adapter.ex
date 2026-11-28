defmodule BnestApp.Behaviour.ReleaseAndDeploy.IntegrationAdapter do
  @moduledoc """
  The integration layer's adapter for `release_and_deploy.feature`. It runs
  the same pure model the unit adapter drives: the real boundaries the review
  binds (child processes with doubles, the service managers, the temporary
  release host) are proven by the Node suites in
  `apps/bnest-app/tools/release.test.mjs`, which the scenarios name as their
  alternative proof. The ExBdd integration execution therefore proves the
  scenario logic, never a second copy of the process harness.
  """

  alias BnestApp.Behaviour.ReleaseAndDeploy.UnitAdapter, as: Unit

  @doc "Installs the model and this adapter in the scenario context."
  def install(context) do
    context
    |> Map.put(:commands_adapter, __MODULE__)
    |> Map.put(:commands, %{})
  end

  @doc "Nothing to release: the model is discarded with the scenario context."
  def release(context), do: context

  defdelegate record_host(context), to: Unit
  defdelegate run_release(context), to: Unit
  defdelegate assert_call_order(context, order), to: Unit
  defdelegate assert_json_result(context, outcome), to: Unit
  defdelegate throwing_host(context, category, outcome), to: Unit
  defdelegate assert_exit_status(context, outcome, status), to: Unit
  defdelegate release_arguments(context, args), to: Unit
  defdelegate parse_arguments(context), to: Unit
  defdelegate assert_refused_exit(context, message), to: Unit
  defdelegate assert_no_host(context), to: Unit
  defdelegate artifact_state(context, revision, artifact, worktree), to: Unit
  defdelegate run_artifact_command(context, command), to: Unit
  defdelegate assert_artifact_calls(context, calls, prints), to: Unit
  defdelegate assert_artifact_failure(context, message), to: Unit
  defdelegate slot_arguments(context, command, args, state), to: Unit
  defdelegate run_slot_command(context), to: Unit
  defdelegate assert_slot_calls(context, calls, refusal), to: Unit
  defdelegate readiness_report(context, slot, report), to: Unit
  defdelegate run_readiness(context), to: Unit
  defdelegate assert_wait(context, ending), to: Unit
  defdelegate previous_slot(context, previous), to: Unit
  defdelegate run_rollback(context), to: Unit
  defdelegate assert_rollback(context, active, refusal), to: Unit
  defdelegate retire_context(context, platform, active), to: Unit
  defdelegate run_retire(context, slot), to: Unit
  defdelegate assert_retire(context, stopped, refusal), to: Unit
  defdelegate deployment_arguments(context, args), to: Unit
  defdelegate run_dispatcher(context), to: Unit
  defdelegate assert_dispatcher_refusal(context, message), to: Unit
  defdelegate config_values(context, root, origin), to: Unit
  defdelegate check_configuration(context), to: Unit
  defdelegate assert_config_refusal(context, message), to: Unit
  defdelegate assert_release_configuration(context), to: Unit
  defdelegate record_build_runs(context), to: Unit
  defdelegate run_builds(context), to: Unit
  defdelegate assert_worktrees(context), to: Unit
  defdelegate platform_is(context, platform), to: Unit
  defdelegate pick_adapter(context), to: Unit
  defdelegate assert_adapter(context, adapter, message), to: Unit
end
