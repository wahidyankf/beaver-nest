defmodule BnestApp.Behaviour.ReleaseAndDeployTest do
  @moduledoc """
  Unit tests for the `release_and_deploy.feature` model and adapter. Every
  scenario of the feature carries a `@scenario` reference below, so the
  behaviour coverage check sees the unit binding the review requires.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.ReleaseAndDeploy.UnitAdapter, as: Adapter
  alias BnestApp.Behaviour.ReleaseAndDeployModel, as: Model

  defp context, do: Adapter.install(%{})

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:run builds an immutable artifact, promotes it, and prints one JSON result
  test "a passing release runs every step once and prints one JSON line" do
    assert Model.release_steps() == [
             "preflight",
             "gates",
             "build",
             "migration",
             "prepare",
             "promote",
             "routed",
             "drain",
             "converge"
           ]

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
    assert Model.exit_code_for("passed") == 0
    assert Model.exit_code_for("queued") == 0
    assert Model.exit_code_for("deferred") == 0
    assert Model.exit_code_for("failed") == 1
    assert Model.exit_code_for("rolled-back") == 1

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
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:run fails closed when --mode is passed at all, with an error naming its removal
  test "the --mode=<value> form fails closed too, and a plain release argv still parses" do
    message =
      "The --mode flag was removed with the family-chat release stages; run release:run without --mode"

    assert Model.parse_arguments(["--mode=experience"]) == {:error, "configuration", message}
    assert Model.parse_arguments(["--mode="]) == {:error, "configuration", message}

    assert Model.parse_arguments(["--revision", "0123456789abcdef0123456789abcdef01234567"]) ==
             :ok
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: release:build, release:migrate, and release:converge each run one step against the immutable artifact
  test "artifact steps run once each and refuse missing artifacts" do
    revision = "0123456789abcdef0123456789abcdef01234567"

    for {command, artifact, worktree, calls, prints, failure} <- [
          {"release:build", "missing", "isolated", "npm ci, mix release steps, copy artifact",
           revision, "none"},
          {"release:build", "present", "isolated", "(none)", "(none)",
           "Release #{revision} already exists; refuse to overwrite an immutable artifact."},
          {"release:build", "missing", "inside checkout", "(none)", "(none)",
           "BNEST_DEPLOY_WORKTREE must be an isolated Git worktree."},
          {"release:migrate", "present", "(none)",
           "migration eval with the production environment", "(none)", "none"},
          {"release:migrate", "missing", "(none)", "(none)", "(none)",
           "Release #{revision} does not exist."},
          {"release:converge", "present", "(none)",
           "converge eval with the production environment", "(none)", "none"},
          {"release:converge", "missing", "(none)", "(none)", "(none)",
           "Release #{revision} does not exist."}
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
          {"deploy:prepare", "--slot blue --revision #{revision}", "fresh",
           "install service, await ready, write metadata", "none"},
          {"deploy:prepare", "--slot green --revision #{revision}", "fresh",
           "install service, await ready, write metadata", "none"},
          {"deploy:prepare", "--slot teal --revision #{revision}", "fresh", "(none)",
           "--slot must be blue or green."},
          {"deploy:prepare", "--slot blue", "fresh", "(none)",
           "--revision is required; run release:build first."},
          {"deploy:prepare", "", "fresh", "(none)", "--slot must be blue or green."},
          {"deploy:promote", "--slot green", "blue active, green ready",
           "write Caddyfile, validate, reload, write state, print status", "none"},
          {"deploy:promote", "--slot blue", "blue active, green ready", "(none)",
           "blue is already active."},
          {"deploy:promote", "--slot green", "blue active, green missing", "(none)",
           "green has not been prepared."},
          {"deploy:promote", "--slot teal", "blue active, green ready", "(none)",
           "--slot must be blue or green."},
          {"deploy:promote", "--slot blue", "fresh", "(none)", "blue has not been prepared."}
        ] do
      context()
      |> Adapter.slot_arguments(command, args, state)
      |> Adapter.run_slot_command()
      |> Adapter.assert_slot_calls(calls, refusal)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: Promotion waits up to 60 seconds for the slot to report its revision
  test "promotion waits for the slot revision or times out at 60 seconds" do
    context()
    |> Adapter.readiness_report("blue", "the revision at once")
    |> Adapter.run_readiness()
    |> Adapter.assert_wait("ready")

    context()
    |> Adapter.readiness_report("green", "another revision")
    |> Adapter.run_readiness()
    |> Adapter.assert_wait("green did not become ready within 60 seconds.")

    assert Model.await_ready("green", "rev", []) ==
             {:timeout, "green did not become ready within 60 seconds."}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:rollback returns traffic to the previous slot or refuses
  test "rollback returns traffic to the previous slot or refuses" do
    context()
    |> Adapter.previous_slot("blue")
    |> Adapter.run_rollback()
    |> Adapter.assert_rollback("blue", "none")

    context()
    |> Adapter.previous_slot("(none)")
    |> Adapter.run_rollback()
    |> Adapter.assert_rollback("(none)", "No previous slot is available for rollback.")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: deploy:retire stops a slot through the platform service adapter and refuses the active slot
  test "retire stops the slot through the platform adapter and refuses the active slot" do
    for {platform, stopped} <- [
          {"linux", "green through systemctl --user disable --now"},
          {"darwin", "green through launchctl bootout"}
        ] do
      context()
      |> Adapter.retire_context(platform, "blue")
      |> Adapter.run_retire("green")
      |> Adapter.assert_retire(stopped, "none")
    end

    context()
    |> Adapter.retire_context("linux", "blue")
    |> Adapter.run_retire("blue")
    |> Adapter.assert_retire("(none)", "Refuse to retire the active slot.")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A missing revision or an unknown deployment command is refused
  test "the dispatcher refuses missing revisions and unknown commands" do
    for {args, message} <- [
          {"deploy:prepare --slot blue", "--revision is required; run release:build first."},
          {"release:migrate", "--revision is required; run release:build first."},
          {"release:converge", "--revision is required; run release:build first."},
          {"deploy:unknown", "Unknown deployment command: deploy:unknown"},
          {"(no arguments)", "Unknown deployment command: (missing)"}
        ] do
      context()
      |> Adapter.deployment_arguments(args)
      |> Adapter.run_dispatcher()
      |> Adapter.assert_dispatcher_refusal(message)
    end

    assert Model.dispatch([]) == {:error, "Unknown deployment command: (missing)"}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: A deploy root inside the repository or a production origin that is not a bare HTTPS origin is refused
  test "a bad deploy root or origin is refused, including under release:run" do
    # The unit layer carries no URL literals, so it proves the deploy-root
    # refusals and the missing-origin refusal here; the bare-HTTPS-origin
    # matrix is proven at the integration layer, where URL test data is
    # allowed.
    for {root, origin, message} <- [
          {"inside checkout", "(missing)",
           "BNEST_DEPLOY_ROOT must be outside the repository working tree."},
          {"(missing)", "(missing)",
           "BNEST_DEPLOY_ROOT must point to machine-local deployment state."},
          {"/tmp/bnest-deploy", "(missing)",
           "BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin."}
        ] do
      context()
      |> Adapter.config_values(root, origin)
      |> Adapter.check_configuration()
      |> Adapter.assert_config_refusal(message)
      |> Adapter.assert_release_configuration()
    end

    assert Model.configuration_error() == %{category: "configuration", outcome: "failed"}
    assert Model.exit_code_for("failed") == 1
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
    assert Model.service_adapter("darwin") == {:ok, "launchd"}
    assert Model.service_adapter("linux") == {:ok, "systemd"}

    for platform <- ["win32", "freebsd"] do
      context()
      |> Adapter.platform_is(platform)
      |> Adapter.pick_adapter()
      |> Adapter.assert_adapter(
        "(none)",
        "unsupported platform \"#{platform}\": the release tool supports darwin (launchd) and linux (systemd) only."
      )
    end

    context()
    |> Adapter.platform_is("linux")
    |> Adapter.pick_adapter()
    |> Adapter.assert_adapter("systemd", "none")
  end
end
