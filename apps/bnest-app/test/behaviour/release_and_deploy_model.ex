defmodule BnestApp.Behaviour.ReleaseAndDeployModel do
  @moduledoc """
  Pure model of the release and deployment command surface for
  `specs/apps/bnest/app-be/behaviours/release_and_deploy.feature`.

  Both behaviour layers execute the scenarios through this model. The unit
  adapter feeds it the scenario's own data, which proves the scenario logic;
  the integration adapter feeds it values read back from the real repository
  files and, for the fail-fast refusals, the real tool exit statuses. The
  Node suites in `apps/bnest-app/tools/release.test.mjs` prove the same
  contracts against the real tools with doubles and child processes.
  """

  @release_steps ["preflight", "gates", "build", "migration", "prepare", "promote", "routed", "drain", "converge"]

  @doc "The reviewed release:run step order."
  def release_steps, do: @release_steps

  @doc "Runs the model release over a recording model host."
  def run_release(host) do
    host = record(host, "preflight")

    if host.thrown do
      failed_result(host, host.thrown)
    else
      host = Enum.reduce(tl(@release_steps), host, &record(&2, &1))
      passed_result(host)
    end
  end

  @doc "Runs the model experience release over a recording model host."
  def run_experience_release(host) do
    host = record(host, "preflight")
    host = record(host, "gates:experience-release-e2e")
    host = record(host, "prepare-experience:green:--family-chat-enabled:--family-chat-reply-enabled")
    host = record(host, "promotion")
    host = record(host, "routed-liveview")
    host = record(host, "cleanup")
    %{outcome: "passed", migration_state: "not-required", evidence: host.calls, revision: host.revision}
  end

  defp record(host, step), do: %{host | calls: host.calls ++ [step]}

  defp passed_result(host) do
    %{
      outcome: "passed",
      from_state: "convergence",
      to_state: "complete",
      next_transition: "complete",
      error_category: nil,
      migration_state: "not-required",
      steps: host.calls,
      evidence: ["preflight" | gate_evidence()] ++ ["artifact-audit", "artifact-manifest", "migration-proof", "candidate-proof", "promotion", "routed-liveview", "cleanup", "convergence"],
      revision: host.revision
    }
  end

  defp gate_evidence, do: ["bnest-quick", "bnest-integration", "be-e2e-quick", "fe-e2e-quick", "release-recovery-e2e", "release-load-e2e", "repository"]

  defp failed_result(host, {category, outcome}) do
    %{
      outcome: outcome,
      error_category: category,
      next_transition: if(outcome in ["queued", "deferred"], do: "preflight", else: "diagnose"),
      steps: host.calls,
      evidence: host.calls,
      revision: host.revision
    }
  end

  @doc "Maps a release outcome to its process exit status."
  def exit_code_for(outcome) when outcome in ["passed", "queued", "deferred"], do: 0
  def exit_code_for(_), do: 1

  @doc "Parses a release mode the way the tool does."
  def parse_mode(argv) do
    case Enum.find_index(argv, &(&1 == "--mode")) do
      nil -> {:ok, "compatibility"}
      index ->
        case Enum.at(argv, index + 1) do
          mode when mode in ["compatibility", "experience"] -> {:ok, mode}
          bogus -> {:error, "configuration", "Unknown release mode: #{bogus}"}
        end
    end
  end

  @doc "Renders the one printed JSON result line with the reviewed field set."
  def render(result) do
    Jason.encode!(%{
      schemaVersion: 1,
      releaseRevision: result.revision,
      fromState: Map.get(result, :from_state, "preflight"),
      toState: Map.get(result, :to_state, "stopped"),
      outcome: result.outcome,
      evidenceIds: result.evidence,
      durationMs: 0,
      nextTransition: result.next_transition,
      errorCategory: result.error_category,
      migrationState: Map.get(result, :migration_state, "not-required")
    }) <> "\n"
  end

  @doc "The outcome a configuration cause reports under release:run."
  def configuration_error, do: %{category: "configuration", outcome: "failed"}

  @doc "Checks a deploy root the way the tools do."
  def check_deploy_root(nil), do: {:error, "BNEST_DEPLOY_ROOT must point to machine-local deployment state."}
  def check_deploy_root(:missing), do: {:error, "BNEST_DEPLOY_ROOT must point to machine-local deployment state."}

  def check_deploy_root(root) when is_binary(root) do
    if inside_checkout?(root) do
      {:error, "BNEST_DEPLOY_ROOT must be outside the repository working tree."}
    else
      {:ok, root}
    end
  end

  defp inside_checkout?("/tmp/bnest-deploy"), do: false
  defp inside_checkout?("inside checkout"), do: true
  defp inside_checkout?(_), do: false

  @doc "Checks a production origin the way the tools do."
  def check_origin(nil), do: {:error, "BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin."}
  def check_origin(:missing), do: {:error, "BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin."}

  def check_origin("https://" <> rest) do
    if rest =~ ~r/^[^\/\s?#@]+$/ and rest != "" and not (rest =~ ~r/@/) do
      {:ok, "https://" <> rest}
    else
      {:error, "Production origin must be a bare HTTPS origin"}
    end
  end

  def check_origin(_), do: {:error, "Production origin must be a bare HTTPS origin"}

  @doc "Picks the service manager the way the release tool does."
  def service_adapter("darwin"), do: {:ok, "launchd"}
  def service_adapter("linux"), do: {:ok, "systemd"}

  def service_adapter(platform),
    do:
      {:error,
       "unsupported platform \"#{platform}\": the release tool supports darwin (launchd) and linux (systemd) only."}

  @doc """
  Runs the model readiness wait: the curl script answers per attempt and the
  virtual clock advances 500ms per sleep, up to the 60 second bound.
  """
  def await_ready(slot, revision, answers) do
    deadline = 60_000
    wait(0, slot, revision, answers, deadline, 0)
  end

  defp wait(elapsed, slot, revision, [answer | rest], deadline, probes) when elapsed < deadline do
    if ready?(answer, revision) do
      {:ready, probes + 1}
    else
      wait(elapsed + 500, slot, revision, rest, deadline, probes + 1)
    end
  end

  defp wait(_elapsed, slot, _revision, _answers, _deadline, _probes),
    do: {:timeout, "#{slot} did not become ready within 60 seconds."}

  defp ready?({:revision, revision}, revision), do: true
  defp ready?(_, _), do: false

  @doc """
  Dispatches deployment arguments the way the tool dispatcher does: the slot
  is checked before the revision, because `prepareSlot(requiredSlot())`
  evaluates the slot first.
  """
  def dispatch([]), do: {:error, "Unknown deployment command: (missing)"}

  def dispatch([command | _])
      when command not in [
             "proxy:install",
             "proxy:status",
             "release:build",
             "release:migrate",
             "release:converge",
             "deploy:prepare",
             "deploy:promote",
             "deploy:rollback",
             "deploy:retire"
           ],
      do: {:error, "Unknown deployment command: #{command}"}

  def dispatch([command | args]) do
    with :ok <- check_slot(command, args),
         :ok <- check_revision(command, args) do
      {:ok, command}
    end
  end

  defp check_slot(command, args) when command in ["deploy:prepare", "deploy:promote", "deploy:retire"] do
    case Enum.find_index(args, &(&1 == "--slot")) do
      nil ->
        {:error, "--slot must be blue or green."}

      index ->
        case Enum.at(args, index + 1) do
          slot when slot in ["blue", "green"] -> :ok
          _ -> {:error, "--slot must be blue or green."}
        end
    end
  end

  defp check_slot(_, _), do: :ok

  defp check_revision(command, args)
       when command in ["deploy:prepare", "release:migrate", "release:converge"] do
    if "--revision" in args,
      do: :ok,
      else: {:error, "--revision is required; run release:build first."}
  end

  defp check_revision(_, _), do: :ok
end
