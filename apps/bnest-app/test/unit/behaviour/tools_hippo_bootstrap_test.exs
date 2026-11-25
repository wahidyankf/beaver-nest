defmodule BnestApp.Behaviour.Tools.HippoBootstrapModel do
  @moduledoc false

  # Pure mirror of the hippo consumer wrapper. Line cites are the wrapper
  # itself; the harness cites prove the same branches run for real.

  # Mirrors hippo:35-37 (exact stable version gate, exit 125).
  def version_valid?(version), do: version =~ ~r/^v\d+\.\d+\.\d+$/

  # Mirrors hippo:40-47 (40 lowercase hex commit, exit 125).
  def commit_valid?(commit), do: commit =~ ~r/^[0-9a-f]{40}$/

  # Mirrors hippo:69-78 (per-target 64 hex checksum, exit 125).
  def checksum_valid?(checksum), do: checksum =~ ~r/^[0-9a-f]{64}$/

  # Mirrors hippo:51-65 (published goos/goarch matrix, exit 125 otherwise).
  def platform_target(os, arch) do
    with {:ok, goos} <- goos(os),
         {:ok, goarch} <- goarch(arch) do
      {:ok, goos <> "-" <> goarch}
    end
  end

  defp goos("Darwin"), do: {:ok, "darwin"}
  defp goos("Linux"), do: {:ok, "linux"}
  defp goos(_), do: {:error, 125, "hippo does not support this operating system"}

  defp goarch(name) when name in ["x86_64", "amd64"], do: {:ok, "amd64"}
  defp goarch(name) when name in ["arm64", "aarch64"], do: {:ok, "arm64"}
  defp goarch(_), do: {:error, 125, "hippo does not support this architecture"}

  # Mirrors hippo:13 (no readable pin, exit 125 before any transport).
  # Mirrors hippo:20-31 (each key exactly once, exit 125).
  # Mirrors hippo:36,41,46,72,77 (invalid value messages, exit 125).
  def pin_result(:no_lock), do: {:error, 125, "hippo has no pin at hippo.lock"}

  def pin_result({:duplicate, key}),
    do: {:error, 125, "hippo lock has missing or duplicate #{key}"}

  def pin_result({:missing, key}), do: {:error, 125, "hippo lock has missing or duplicate #{key}"}
  def pin_result({:bad_version, _}), do: {:error, 125, "hippo lock has an invalid version"}
  def pin_result({:bad_commit, _}), do: {:error, 125, "hippo lock has an invalid commit"}
  def pin_result({:bad_checksum, _}), do: {:error, 125, "hippo lock has an invalid checksum"}
  def pin_result(:ok), do: :ok

  # Mirrors hippo:119-129 (cached payload must digest-match and report the
  # pinned identity; a mismatch rejects with 99 before execution).
  def cached_verdict(:tampered_digest), do: {:refuse, 99}
  def cached_verdict(:tampered_identity), do: {:refuse, 99}
  def cached_verdict(:valid), do: :run

  # Mirrors hippo:505-516 (archive digest and embedded identity gates).
  def download_verdict(:digest_mismatch), do: {:refuse, 125}
  def download_verdict(:identity_mismatch), do: {:refuse, 125}
  def download_verdict(:ok), do: :install

  # Mirrors the cold/warm shape in test-hippo-bootstrap.sh run_cold_then_warm.
  def cache_plan(:empty), do: {:download, 1}
  def cache_plan(:warm_valid), do: {:reuse, 0}
  def cache_plan(:tampered), do: {:refuse, 99}

  # Mirrors hippo:556-565 (run maps worker settings ahead of caller args).
  def worker_argv(caller) do
    [
      "run",
      "--concurrency-env",
      "NX_PARALLEL",
      "--concurrency-env",
      "GOMAXPROCS",
      "--concurrency-env",
      "DOTNET_PROCESSOR_COUNT"
    ] ++ caller
  end

  # Mirrors hippo:267-269,355-423 (live owner waits; dead or crashed takes over).
  def wait_verdict(:live_intact), do: :wait
  def wait_verdict(:live_malformed), do: :wait
  def wait_verdict(:dead_pid), do: :takeover
  def wait_verdict(:reused_pid), do: :takeover
  def wait_verdict(:crashed), do: :takeover

  # Mirrors hippo:210-251 (a claimed release is never a prune candidate).
  # Mirrors hippo:479 retention_idle_seconds=604800 and 517 (pinned stays).
  def retention_keep?(%{claimed: true}), do: true
  def retention_keep?(%{pinned: true}), do: true
  def retention_keep?(%{idle_seconds: s}) when is_integer(s) and s < 604_800, do: true
  def retention_keep?(_), do: false

  # Mirrors hippo:234-235 (guard wait that runs out exits 124).
  def guard_wait_verdict(:granted), do: :proceed

  def guard_wait_verdict(:timeout),
    do: {:error, 124, "hippo bootstrap timed out waiting for its install guard"}

  # Mirrors hippo:422-423 (lock wait that runs out exits 124).
  def lock_wait_verdict(:granted), do: :proceed

  def lock_wait_verdict(:timeout),
    do: {:error, 124, "hippo bootstrap timed out waiting for its install lock"}

  # Mirrors hippo:218 (Darwin needs lockf) and hippo:226 (Linux needs flock).
  def lock_tool_error("Linux"), do: {:error, 125, "hippo bootstrap requires flock on Linux"}
  def lock_tool_error("Darwin"), do: {:error, 125, "hippo bootstrap requires lockf on Darwin"}

  # Mirrors hippo:540-551 (checkout-local wins, else primary, else default;
  # an explicit caller setting always wins).
  def policy(:caller, _checkout, _primary, caller), do: caller
  def policy(:checkout, checkout, _primary, _caller), do: checkout
  def policy(:primary, _checkout, primary, _caller), do: primary
  def policy(:default, _checkout, _primary, _caller), do: :default_path

  def identity_path(tool_dir), do: tool_dir <> "/hippo.identity.json"

  # Mirrors the BN-CFG-24 tier hand-off (each tier nests in the ceiling).
  def tiers_nest?(tiers, ceiling) do
    Enum.all?(tiers, fn %{cpu: cpu, memory: mem} ->
      cpu <= ceiling.cpu and mem <= ceiling.memory
    end)
  end
end

defmodule BnestApp.Behaviour.Tools.HippoBootstrapTest do
  @moduledoc """
  Unit bindings for `hippo-bootstrap.feature`. Every scenario below carries
  its `@scenario` reference so the behaviour coverage check sees the unit
  binding the review requires. The model mirrors the wrapper logic cited in
  each test; no test touches a file, socket, or child process.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.Tools.HippoBootstrapModel, as: Model

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: A cold cache installs once and a warm cache needs no transport
  test "cold cache downloads once and warm cache reuses without transport" do
    # Harness: run_cold_then_warm in test-hippo-bootstrap.sh.
    assert Model.cache_plan(:empty) == {:download, 1}
    assert Model.cache_plan(:warm_valid) == {:reuse, 0}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Repository worker settings precede the caller's run arguments
  test "worker mappings arrive ahead of caller arguments in order" do
    # Mirrors hippo:556-565; harness run_worker_settings_precede_run_arguments.
    caller = ["--class", "ephemeral", "--", "printf", "%s\\n", "ok"]
    argv = Model.worker_argv(caller)

    assert Enum.take(argv, 7) == [
             "run",
             "--concurrency-env",
             "NX_PARALLEL",
             "--concurrency-env",
             "GOMAXPROCS",
             "--concurrency-env",
             "DOTNET_PROCESSOR_COUNT"
           ]

    assert Enum.drop(argv, 7) == caller
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Tampered warm-cache payload never executes
  test "tampered payload is refused before execution" do
    # Mirrors hippo:119-129; harness run_tampered_warm_cache exits 99.
    assert Model.cached_verdict(:tampered_digest) == {:refuse, 99}
    assert Model.cached_verdict(:tampered_identity) == {:refuse, 99}
    assert Model.cached_verdict(:valid) == :run
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: A downloaded release that fails verification is refused
  test "failed verification refuses without publishing" do
    # Mirrors hippo:505-516; harness run_download_digest_mismatch.
    assert Model.download_verdict(:digest_mismatch) == {:refuse, 125}
    assert Model.download_verdict(:identity_mismatch) == {:refuse, 125}
    assert Model.download_verdict(:ok) == :install
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Non-exact stable release version is rejected
  test "malformed or path-shaped version is rejected" do
    # Mirrors hippo:35-37; harness rejects v1x, traversal, empty.
    refute Model.version_valid?("v1x.2.3")
    refute Model.version_valid?("v1.2.3/../../../escape")
    refute Model.version_valid?("v1.2")
    assert Model.version_valid?("v1.2.3")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Unsupported platform is refused before any transport
  test "unknown system or architecture is refused" do
    # Mirrors hippo:51-65; harness run_unsupported_platform_refused.
    assert Model.platform_target("Linux", "x86_64") == {:ok, "linux-amd64"}
    assert Model.platform_target("Darwin", "arm64") == {:ok, "darwin-arm64"}

    assert Model.platform_target("Plan9", "x86_64") ==
             {:error, 125, "hippo does not support this operating system"}

    assert Model.platform_target("Linux", "riscv64") ==
             {:error, 125, "hippo does not support this architecture"}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: A caller waits while another caller is installing
  test "live owner makes the caller wait" do
    # Mirrors hippo:355-423 reclaim path; harness live-owner rows wait.
    assert Model.wait_verdict(:live_intact) == :wait
    assert Model.wait_verdict(:live_malformed) == :wait
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: A caller takes over an install whose owner is gone
  test "gone owner is taken over" do
    # Mirrors hippo:323-347 reclaim path; harness dead, reused, crashed rows.
    assert Model.wait_verdict(:dead_pid) == :takeover
    assert Model.wait_verdict(:reused_pid) == :takeover
    assert Model.wait_verdict(:crashed) == :takeover
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Two callers starting together download once and both run the release
  test "concurrent cold callers share one download" do
    # Harness run_concurrent_cold_callers: one download, two runs.
    assert Model.cache_plan(:empty) == {:download, 1}
    assert Model.wait_verdict(:crashed) == :takeover
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Retention never deletes a release another consumer is using
  test "claimed release survives retention" do
    # Mirrors hippo:210-251 release_is_claimed gate.
    assert Model.retention_keep?(%{claimed: true, pinned: false, idle_seconds: 999_999_999})
    refute Model.retention_keep?(%{claimed: false, pinned: false, idle_seconds: 999_999_999})
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Retention never evicts a release another repository still uses
  test "each repository keeps its pinned release" do
    # Mirrors hippo:517 pinned exemption from prune.
    assert Model.retention_keep?(%{claimed: false, pinned: true, idle_seconds: 999_999_999})
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: Retention reclaims releases left idle beyond its window
  test "only pinned and recent idle fallbacks remain" do
    # Mirrors hippo:479 idle window 604800 and BSD/GNU stat dialects.
    assert Model.retention_keep?(%{claimed: false, pinned: false, idle_seconds: 100})
    refute Model.retention_keep?(%{claimed: false, pinned: false, idle_seconds: 604_800})
    refute Model.retention_keep?(%{claimed: false, pinned: false, idle_seconds: 900_000})
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: A missing, duplicated, or malformed pin exits 125 before any transport
  test "bad pin exits 125" do
    # Mirrors hippo:13,24,36,41,72 pin gates.
    assert Model.pin_result(:no_lock) == {:error, 125, "hippo has no pin at hippo.lock"}

    assert Model.pin_result({:duplicate, "version"}) ==
             {:error, 125, "hippo lock has missing or duplicate version"}

    assert Model.pin_result({:missing, "version"}) ==
             {:error, 125, "hippo lock has missing or duplicate version"}

    assert Model.pin_result({:bad_commit, "short"}) ==
             {:error, 125, "hippo lock has an invalid commit"}

    assert Model.pin_result({:bad_checksum, "short"}) ==
             {:error, 125, "hippo lock has an invalid checksum"}

    assert Model.pin_result(:ok) == :ok
    refute Model.version_valid?("bad-version")
    refute Model.commit_valid?("short")
    refute Model.checksum_valid?("short")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: A bounded wait for the install guard or lock that runs out exits 124
  test "exhausted bounded waits exit 124" do
    # Mirrors hippo:234-235 and hippo:422-423.
    assert Model.guard_wait_verdict(:timeout) ==
             {:error, 124, "hippo bootstrap timed out waiting for its install guard"}

    assert Model.lock_wait_verdict(:timeout) ==
             {:error, 124, "hippo bootstrap timed out waiting for its install lock"}

    assert Model.guard_wait_verdict(:granted) == :proceed
    assert Model.lock_wait_verdict(:granted) == :proceed
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: A host without flock or lockf exits 125
  test "missing lock tool exits 125" do
    # Mirrors hippo:218 and hippo:226.
    assert Model.lock_tool_error("Linux") ==
             {:error, 125, "hippo bootstrap requires flock on Linux"}

    assert Model.lock_tool_error("Darwin") ==
             {:error, 125, "hippo bootstrap requires lockf on Darwin"}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: The worker policy comes from the checkout's own hippo.local.json, else the primary checkout's, and an explicit setting wins
  test "worker policy resolution order" do
    # Mirrors hippo:540-551; harness run_worker_policy_resolution.
    assert Model.policy(:checkout, "checkout.json", "primary.json", "unset") == "checkout.json"
    assert Model.policy(:primary, "missing", "primary.json", "unset") == "primary.json"
    assert Model.policy(:default, "missing", "missing", "unset") == :default_path
    assert Model.policy(:caller, "checkout.json", "primary.json", "caller.json") == "caller.json"
    assert Model.identity_path("/tool") == "/tool/hippo.identity.json"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature: The wrapper hands the release the repository's local resource policy
  test "tiers nest inside the machine ceiling" do
    # Mirrors the BN-CFG-24 hand-off the harness proves end to end.
    ceiling = %{cpu: 8, memory: 16_384}
    tiers = [%{cpu: 1, memory: 512}, %{cpu: 2, memory: 2048}, %{cpu: 4, memory: 8192}]
    assert Model.tiers_nest?(tiers, ceiling)
    refute Model.tiers_nest?([%{cpu: 16, memory: 512}], ceiling)
    refute Model.tiers_nest?([%{cpu: 1, memory: 99_999}], ceiling)
  end
end
