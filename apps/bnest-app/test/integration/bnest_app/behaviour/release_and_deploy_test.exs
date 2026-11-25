defmodule BnestApp.Behaviour.ReleaseAndDeployIntegrationTest do
  @moduledoc """
  Integration tests for the `release_and_deploy.feature` adapter. The
  adapter runs the same pure model the unit adapter drives; the real
  boundaries (child processes with doubles, service managers, the release
  host) are proven by the Node suites, which the scenarios name as their
  alternative proof. URL test data is allowed at this layer, so the
  bare-HTTPS-origin matrix lives here.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.ReleaseAndDeploy.IntegrationAdapter, as: Adapter
  alias BnestApp.Behaviour.ReleaseAndDeployModel, as: Model

  defp context, do: Adapter.install(%{})

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:run builds an immutable artifact, promotes it, and prints one JSON result
  test "a passing release runs every step once" do
    context()
    |> Adapter.record_host()
    |> Adapter.run_release()
    |> Adapter.assert_call_order(
      "preflight gates build migration prepare promote routed drain converge"
    )
    |> Adapter.assert_json_result("passed")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release exits 0 for passed, queued, and deferred and 1 for every other outcome
  test "only terminal failures exit 1" do
    for {category, outcome, status} <- [
          {"(none)", "passed", 0},
          {"concurrency", "queued", 0},
          {"capacity", "deferred", 0},
          {"preflight", "failed", 1},
          {"concurrency", "rolled-back", 1}
        ] do
      context()
      |> Adapter.throwing_host(category, outcome)
      |> Adapter.run_release()
      |> Adapter.assert_exit_status(outcome, status)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:run fails closed when --mode is passed at all, with an error naming its removal
  test "a removed --mode flag fails closed before any host exists" do
    context()
    |> Adapter.release_arguments(
      "--mode experience --revision 0123456789abcdef0123456789abcdef01234567"
    )
    |> Adapter.parse_arguments()
    |> Adapter.assert_refused_exit(
      "The --mode flag was removed with the family-chat release stages; run release:run without --mode"
    )
    |> Adapter.assert_no_host()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:build, release:migrate, and release:converge each run one step against the immutable artifact
  test "artifact steps run once each and refuse missing artifacts" do
    revision = "0123456789abcdef0123456789abcdef01234567"

    for {command, artifact, worktree, calls, prints, failure} <- [
          {"release:build", "missing", "isolated", "npm ci, mix release steps, copy artifact",
           revision, "none"},
          {"release:migrate", "present", "(none)",
           "migration eval with the production environment", "(none)", "none"},
          {"release:converge", "present", "(none)",
           "converge eval with the production environment", "(none)", "none"}
        ] do
      context()
      |> Adapter.artifact_state(revision, artifact, worktree)
      |> Adapter.run_artifact_command(command)
      |> Adapter.assert_artifact_calls(calls, prints)
      |> Adapter.assert_artifact_failure(failure)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:prepare and deploy:promote take a blue or green slot
  test "slot commands take only blue or green" do
    revision = "0123456789abcdef0123456789abcdef01234567"

    for {command, args, state, calls, refusal} <- [
          {"deploy:prepare", "--slot green --revision #{revision}", "fresh",
           "install service, await ready, write metadata", "none"},
          {"deploy:promote", "--slot green", "blue active, green ready",
           "write Caddyfile, validate, reload, write state, print status", "none"},
          {"deploy:prepare", "--slot blue", "fresh", "(none)",
           "--revision is required; run release:build first."}
        ] do
      context()
      |> Adapter.slot_arguments(command, args, state)
      |> Adapter.run_slot_command()
      |> Adapter.assert_slot_calls(calls, refusal)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: Promotion waits up to 60 seconds for the slot to report its revision
  test "promotion waits for the slot revision" do
    context()
    |> Adapter.readiness_report("blue", "the revision at once")
    |> Adapter.run_readiness()
    |> Adapter.assert_wait("ready")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:rollback returns traffic to the previous slot or refuses
  test "rollback returns traffic to the previous slot or refuses" do
    context()
    |> Adapter.previous_slot("blue")
    |> Adapter.run_rollback()
    |> Adapter.assert_rollback("blue", "none")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:retire stops a slot through the platform service adapter and refuses the active slot
  test "retire stops the slot through the platform adapter" do
    context()
    |> Adapter.retire_context("linux", "blue")
    |> Adapter.run_retire("green")
    |> Adapter.assert_retire("green through systemctl --user disable --now", "none")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A missing revision or an unknown deployment command is refused
  test "the dispatcher refuses missing revisions and unknown commands" do
    for {args, message} <- [
          {"deploy:prepare --slot blue", "--revision is required; run release:build first."},
          {"deploy:unknown", "Unknown deployment command: deploy:unknown"}
        ] do
      context()
      |> Adapter.deployment_arguments(args)
      |> Adapter.run_dispatcher()
      |> Adapter.assert_dispatcher_refusal(message)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A deploy root inside the repository or a production origin that is not a bare HTTPS origin is refused
  test "a bad production origin is refused, including under release:run" do
    for {origin, message} <- [
          {"https://service.example/path", "Production origin must be a bare HTTPS origin"},
          {"http://service.example", "Production origin must be a bare HTTPS origin"},
          {"https://user@service.example", "Production origin must be a bare HTTPS origin"}
        ] do
      context()
      |> Adapter.config_values("/tmp/bnest-deploy", origin)
      |> Adapter.check_configuration()
      |> Adapter.assert_config_refusal(message)
      |> Adapter.assert_release_configuration()
    end

    assert Model.check_origin("https://service.example") == {:ok, "https://service.example"}
    assert Model.service_adapter("win32") |> elem(0) == :error
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: The release builds in a detached worktree and removes it afterwards, also when the build fails
  test "both builds add and remove the same detached worktree" do
    context()
    |> Adapter.record_build_runs()
    |> Adapter.run_builds()
    |> Adapter.assert_worktrees()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: The release tool picks the service manager for the platform and stops on any other platform
  test "the release tool picks the service manager for the platform" do
    context()
    |> Adapter.platform_is("darwin")
    |> Adapter.pick_adapter()
    |> Adapter.assert_adapter("launchd", "none")
  end
end
