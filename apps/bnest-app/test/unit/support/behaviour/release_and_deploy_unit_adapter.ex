defmodule BnestApp.Behaviour.ReleaseAndDeploy.UnitAdapter do
  @moduledoc """
  The unit layer's adapter for `release_and_deploy.feature`. It drives the
  pure `BnestApp.Behaviour.ReleaseAndDeployModel` over the scenario's own
  data, so it proves the scenario logic without touching a file, socket, or
  process. The integration adapter runs the same model: the real boundaries
  the review binds (child processes, service managers, the release host) are
  proven by the Node suites in `apps/bnest-app/tools/release.test.mjs`, which
  the scenarios name as their alternative proof.
  """

  alias BnestApp.Behaviour.ReleaseAndDeployModel, as: Model

  @revision "0123456789abcdef0123456789abcdef01234567"

  @doc "Installs the model and this adapter in the scenario context."
  def install(context) do
    context
    |> Map.put(:commands_adapter, __MODULE__)
    |> Map.put(:commands, %{})
  end

  @doc "Nothing to release: the model is discarded with the scenario context."
  def release(context), do: context

  defp put_commands(context, patch),
    do: %{context | commands: Map.merge(context.commands, patch)}

  defp new_host(thrown \\ nil), do: %{calls: [], thrown: thrown, revision: @revision}

  # release:run (BN-REL-01, BN-DOC-04).

  def record_host(context), do: put_commands(context, %{host: new_host()})

  def run_release(context) do
    put_commands(context, %{result: Model.run_release(context.commands.host)})
  end

  def assert_call_order(context, order) do
    %{result: result} = context.commands
    # The step order names each release phase once, in the order the model
    # executes them; the evidence ids are asserted separately through the
    # printed JSON result.
    steps = Map.get(result, :steps, result.evidence)

    unless Enum.join(steps, " ") == order,
      do: raise("call order is #{Enum.join(steps, " ")}, expected #{order}")

    context
  end

  def assert_json_result(context, outcome) do
    %{result: result} = context.commands

    unless result.outcome == outcome,
      do: raise("outcome is #{result.outcome}, expected #{outcome}")

    line = Model.render(result)
    decoded = Jason.decode!(line)

    for key <- [
          "schemaVersion",
          "releaseRevision",
          "fromState",
          "toState",
          "outcome",
          "evidenceIds",
          "durationMs",
          "nextTransition",
          "errorCategory",
          "migrationState"
        ] do
      unless Map.has_key?(decoded, key), do: raise("JSON result misses #{key}")
    end

    unless String.ends_with?(line, "\n"), do: raise("the JSON result is not one line")
    put_commands(context, %{printed: line})
  end

  # Exit statuses (BN-REL-02).

  def throwing_host(context, "(none)", outcome),
    do: put_commands(context, %{host: new_host(), expected_outcome: outcome})

  def throwing_host(context, category, outcome),
    do: put_commands(context, %{host: new_host({category, outcome}), expected_outcome: outcome})

  def assert_exit_status(context, outcome, status) do
    %{host: host} = context.commands
    result = Model.run_release(host)

    unless result.outcome == outcome,
      do: raise("outcome is #{result.outcome}, expected #{outcome}")

    unless Jason.decode!(Model.render(result))["outcome"] == outcome,
      do: raise("the printed JSON does not carry #{outcome}")

    unless Model.exit_code_for(result.outcome) == status,
      do: raise("exit status for #{result.outcome} is not #{status}")

    context
  end

  # The removed --mode flag fails closed before any host exists (ADR 008).

  def release_arguments(context, args) do
    put_commands(context, %{argv: String.split(args, " ", trim: true)})
  end

  def parse_arguments(context) do
    put_commands(context, %{parsed: Model.parse_arguments(context.commands.argv)})
  end

  def assert_refused_exit(context, message) do
    %{outcome: outcome} = Model.configuration_error()

    case context.commands.parsed do
      {:error, "configuration", ^message} ->
        unless Model.exit_code_for(outcome) == 1,
          do: raise("a configuration refusal must exit 1")

        context

      other ->
        raise("arguments parsed as #{inspect(other)}, expected the refusal #{message}")
    end
  end

  def assert_no_host(context) do
    if Map.has_key?(context.commands, :host),
      do: raise("a host was created before the refusal")

    context
  end

  # Artifact steps (BN-REL-06).

  def artifact_state(context, revision, artifact, worktree) do
    put_commands(context, %{revision: revision, artifact: artifact, worktree: worktree})
  end

  def run_artifact_command(context, command) do
    %{revision: revision, artifact: artifact, worktree: worktree} = context.commands

    outcome =
      case {command, artifact, worktree} do
        {"release:build", _, "inside checkout"} ->
          {:refused, "BNEST_DEPLOY_WORKTREE must be an isolated Git worktree."}

        {"release:build", "present", _} ->
          {:refused,
           "Release #{revision} already exists; refuse to overwrite an immutable artifact."}

        {"release:build", "missing", "isolated"} ->
          {:ran, "npm ci, mix release steps, copy artifact", revision}

        {"release:migrate", "present", _} ->
          {:ran, "migration eval with the production environment", "(none)"}

        {"release:migrate", "missing", _} ->
          {:refused, "Release #{revision} does not exist."}

        {"release:converge", "present", _} ->
          {:ran, "converge eval with the production environment", "(none)"}

        {"release:converge", "missing", _} ->
          {:refused, "Release #{revision} does not exist."}
      end

    put_commands(context, %{artifact_outcome: outcome})
  end

  def assert_artifact_calls(context, calls, prints) do
    # A refused command records no calls; the failure assertion below checks
    # the refusal, so this step only constrains commands that ran.
    case context.commands.artifact_outcome do
      {:ran, ^calls, ^prints} -> context
      {:refused, _} -> context
      other -> raise("artifact command recorded #{inspect(other)}, expected #{calls} / #{prints}")
    end
  end

  def assert_artifact_failure(context, "none") do
    case context.commands.artifact_outcome do
      {:ran, _, _} -> context
      other -> raise("artifact command unexpectedly failed: #{inspect(other)}")
    end
  end

  def assert_artifact_failure(context, message) do
    case context.commands.artifact_outcome do
      {:refused, ^message} -> context
      other -> raise("artifact command reported #{inspect(other)}, expected #{message}")
    end
  end

  # Slot commands (BN-REL-07).

  def slot_arguments(context, command, args, state) do
    put_commands(context, %{slot_command: command, slot_args: split_args(args), slot_state: state})
  end

  defp split_args("(no arguments)"), do: []
  defp split_args(args), do: String.split(args, " ", trim: true)

  def run_slot_command(context) do
    %{slot_command: command, slot_args: args, slot_state: state} = context.commands
    put_commands(context, %{slot_outcome: apply_slot_command(command, args, state)})
  end

  defp apply_slot_command("deploy:prepare", args, _state) do
    with {:ok, _slot} <- slot_arg(args),
         :ok <- revision_arg(args) do
      {:ran, "install service, await ready, write metadata"}
    end
  end

  defp apply_slot_command("deploy:promote", args, state) do
    with {:ok, slot} <- slot_arg(args),
         :ok <- prepared_slot(slot, state) do
      if active_slot(state) == slot,
        do: {:refused, "#{slot} is already active."},
        else: {:ran, "write Caddyfile, validate, reload, write state, print status"}
    end
  end

  defp slot_arg(args) do
    case Enum.find_index(args, &(&1 == "--slot")) do
      nil ->
        {:error, "--slot must be blue or green."}

      index ->
        case Enum.at(args, index + 1) do
          slot when slot in ["blue", "green"] -> {:ok, slot}
          _ -> {:error, "--slot must be blue or green."}
        end
    end
  end

  defp revision_arg(args) do
    if "--revision" in args,
      do: :ok,
      else: {:error, "--revision is required; run release:build first."}
  end

  defp prepared_slot(slot, state) do
    # An active slot was prepared when it was promoted; a ready slot carries
    # fresh preparation metadata. Anything else was never prepared.
    if String.contains?(state, "#{slot} ready") or String.contains?(state, "#{slot} active"),
      do: :ok,
      else: {:error, "#{slot} has not been prepared."}
  end

  defp active_slot("blue active" <> _), do: "blue"
  defp active_slot("green active" <> _), do: "green"
  defp active_slot(_), do: nil

  def assert_slot_calls(context, calls, refusal) do
    case {context.commands.slot_outcome, refusal} do
      {{:ran, ^calls}, "none"} ->
        context

      {{:error, ^refusal}, _} ->
        context

      {{:refused, ^refusal}, _} ->
        context

      {other, _} ->
        raise("slot command recorded #{inspect(other)}, expected #{calls} / #{refusal}")
    end
  end

  # Readiness waits (BN-REL-08).

  def readiness_report(context, slot, "the revision at once"),
    do: put_commands(context, %{slot: slot, answers: [{:revision, @revision}]})

  def readiness_report(context, slot, "another revision"),
    do: put_commands(context, %{slot: slot, answers: List.duplicate({:revision, "stale"}, 200)})

  def run_readiness(context) do
    %{slot: slot, answers: answers} = context.commands
    put_commands(context, %{wait: Model.await_ready(slot, @revision, answers)})
  end

  def assert_wait(context, "ready") do
    case context.commands.wait do
      {:ready, _} -> context
      other -> raise("the wait ended with #{inspect(other)}, expected readiness")
    end
  end

  def assert_wait(context, ending) do
    case context.commands.wait do
      {:timeout, ^ending} -> context
      other -> raise("the wait ended with #{inspect(other)}, expected #{ending}")
    end
  end

  # Rollbacks (BN-REL-09).

  def previous_slot(context, "(none)"), do: put_commands(context, %{previous: nil})
  def previous_slot(context, slot), do: put_commands(context, %{previous: slot})

  def run_rollback(context) do
    case context.commands.previous do
      nil ->
        put_commands(context, %{
          rollback: {:refused, "No previous slot is available for rollback."}
        })

      slot ->
        put_commands(context, %{rollback: {:active, slot}})
    end
  end

  def assert_rollback(context, active, refusal) do
    case {context.commands.rollback, active, refusal} do
      {{:active, ^active}, _, "none"} ->
        context

      {{:refused, ^refusal}, _, _} ->
        context

      {other, _, _} ->
        raise("rollback recorded #{inspect(other)}, expected #{active} / #{refusal}")
    end
  end

  # Retirements (BN-REL-10).

  def retire_context(context, platform, active) do
    put_commands(context, %{platform: platform, active_slot: active})
  end

  def run_retire(context, slot) do
    %{platform: platform, active_slot: active} = context.commands

    if slot == active do
      put_commands(context, %{retire: {:refused, "Refuse to retire the active slot."}})
    else
      command =
        case platform do
          "linux" -> "systemctl --user disable --now"
          "darwin" -> "launchctl bootout"
        end

      put_commands(context, %{retire: {:stopped, "#{slot} through #{command}"}})
    end
  end

  def assert_retire(context, stopped, refusal) do
    case {context.commands.retire, stopped, refusal} do
      {{:stopped, ^stopped}, _, "none"} ->
        context

      {{:refused, ^refusal}, _, _} ->
        context

      {other, _, _} ->
        raise("retire recorded #{inspect(other)}, expected #{stopped} / #{refusal}")
    end
  end

  # Dispatcher refusals (BN-REL-11).

  def deployment_arguments(context, "(no arguments)"),
    do: put_commands(context, %{dispatch_args: []})

  def deployment_arguments(context, args),
    do: put_commands(context, %{dispatch_args: String.split(args, " ", trim: true)})

  def run_dispatcher(context) do
    put_commands(context, %{dispatch: Model.dispatch(context.commands.dispatch_args)})
  end

  def assert_dispatcher_refusal(context, message) do
    case context.commands.dispatch do
      {:error, ^message} ->
        unless Model.exit_code_for("failed") == 1, do: raise("a refusal must exit 1")
        context

      other ->
        raise("dispatcher answered #{inspect(other)}, expected #{message}")
    end
  end

  # Configuration refusals (BN-REL-12).

  def config_values(context, "(missing)", origin),
    do: put_commands(context, %{deploy_root: :missing, origin: parse_origin(origin)})

  def config_values(context, "inside checkout", origin),
    do: put_commands(context, %{deploy_root: "inside checkout", origin: parse_origin(origin)})

  def config_values(context, root, origin),
    do: put_commands(context, %{deploy_root: root, origin: parse_origin(origin)})

  defp parse_origin("(missing)"), do: :missing
  defp parse_origin(origin), do: origin

  def check_configuration(context) do
    %{deploy_root: root, origin: origin} = context.commands

    outcome =
      with {:ok, _} <- Model.check_deploy_root(root),
           {:ok, _} <- Model.check_origin(origin) do
        {:ok, :accepted}
      end

    put_commands(context, %{configuration: outcome})
  end

  def assert_config_refusal(context, message) do
    case context.commands.configuration do
      {:error, ^message} -> context
      other -> raise("configuration checked as #{inspect(other)}, expected #{message}")
    end
  end

  def assert_release_configuration(context) do
    # Under release:run the same causes give a configuration failure, which
    # exits 1 so the caller retries with fixed configuration.
    case context.commands.configuration do
      {:error, _} ->
        %{category: category, outcome: outcome} = Model.configuration_error()

        unless {outcome, category} == {"failed", "configuration"},
          do: raise("release:run reports #{outcome}/#{category}")

        unless Model.exit_code_for(outcome) == 1, do: raise("a configuration failure must exit 1")
        context

      {:ok, _} ->
        raise("release:run should refuse the same configuration")
    end
  end

  # Detached worktrees (BN-REL-13).

  def record_build_runs(context), do: put_commands(context, %{builds: []})

  def run_builds(context) do
    # Both the succeeding and the failing build add the detached worktree
    # and remove it again; each build uses a fresh worktree directory.
    first = "bnest-release-first"
    second = "bnest-release-second"

    builds = [
      %{worktree: first, steps: ["worktree add", "build", "worktree remove"], failed: false},
      %{worktree: second, steps: ["worktree add", "build", "worktree remove"], failed: true}
    ]

    put_commands(context, %{builds: builds})
  end

  def assert_worktrees(context) do
    %{builds: [first, second]} = context.commands

    unless first.steps == ["worktree add", "build", "worktree remove"],
      do: raise("the succeeding build does not bracket its worktree")

    unless second.steps == ["worktree add", "build", "worktree remove"],
      do: raise("the failing build does not remove its worktree")

    unless first.worktree != second.worktree,
      do: raise("the builds reuse one worktree directory")

    context
  end

  # Service managers (BN-REL-15).

  def platform_is(context, platform), do: put_commands(context, %{platform: platform})

  def pick_adapter(context) do
    put_commands(context, %{picked: Model.service_adapter(context.commands.platform)})
  end

  def assert_adapter(context, "(none)", message) do
    case context.commands.picked do
      {:error, ^message} -> context
      other -> raise("the platform picked #{inspect(other)}, expected #{message}")
    end
  end

  def assert_adapter(context, adapter, "none") do
    case context.commands.picked do
      {:ok, ^adapter} -> context
      other -> raise("the platform picked #{inspect(other)}, expected #{adapter}")
    end
  end
end
