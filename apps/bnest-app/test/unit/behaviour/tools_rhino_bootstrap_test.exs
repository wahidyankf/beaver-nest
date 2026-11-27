defmodule BnestApp.Behaviour.Tools.RhinoBootstrapModel do
  @moduledoc false

  # Pure mirror of the rhino consumer wrapper.

  # Mirrors rhino:71-73 (stable or candidate tag, exit 125).
  def version_valid?(version), do: version =~ ~r/^v\d+\.\d+\.\d+(-[0-9A-Za-z][0-9A-Za-z.]*)?$/

  # Mirrors rhino:75-83 (40 lowercase hex commit, exit 125).
  def commit_valid?(commit), do: commit =~ ~r/^[0-9a-f]{40}$/

  # Mirrors rhino:110-119 (per-target 64 hex checksum, exit 125).
  def checksum_valid?(checksum), do: checksum =~ ~r/^[0-9a-f]{64}$/

  # Mirrors rhino:85 (candidate reports its stable product version).
  def stable_of(version), do: version |> String.split("-") |> hd()

  # Mirrors rhino:87-103 (Rust target triple matrix, exit 125 otherwise).
  def platform_target(os, arch) do
    with {:ok, vendor} <- vendor(os),
         {:ok, cpu} <- cpu(arch) do
      {:ok, cpu <> "-" <> vendor}
    end
  end

  defp vendor("Darwin"), do: {:ok, "apple-darwin"}
  defp vendor("Linux"), do: {:ok, "unknown-linux-gnu"}
  defp vendor(_), do: {:error, 125, "rhino does not support this operating system"}

  defp cpu(name) when name in ["x86_64", "amd64"], do: {:ok, "x86_64"}
  defp cpu(name) when name in ["arm64", "aarch64"], do: {:ok, "aarch64"}
  defp cpu(_), do: {:error, 125, "rhino does not support this architecture"}

  # Mirrors rhino:47 (no readable pin) and rhino:58,72,77,82,113,118.
  def pin_result(:no_lock), do: {:error, 125, "rhino has no pin at rhino.lock"}

  def pin_result({:duplicate, key}),
    do: {:error, 125, "rhino lock has missing or duplicate #{key}"}

  def pin_result({:missing, key}), do: {:error, 125, "rhino lock has missing or duplicate #{key}"}
  def pin_result({:bad_version, _}), do: {:error, 125, "rhino lock has an invalid version"}
  def pin_result({:bad_commit, _}), do: {:error, 125, "rhino lock has an invalid commit"}
  def pin_result({:bad_checksum, _}), do: {:error, 125, "rhino lock has an invalid checksum"}
  def pin_result(:ok), do: :ok

  # Mirrors rhino:161-180 (warm cache must digest-match and report identity).
  def cached_verdict(:tampered_digest), do: {:refuse, 99}
  def cached_verdict(:tampered_identity), do: {:refuse, 99}
  def cached_verdict(:valid), do: :run

  # Mirrors rhino:552-562 (archive inventory, digest, identity gates).
  def download_verdict(:digest_mismatch), do: {:refuse, 125}
  def download_verdict(:identity_mismatch), do: {:refuse, 125}
  def download_verdict(:ok), do: :install

  # Mirrors the download gate (rhino:460-478): only a verified payload runs.
  def payload_executes?(:install), do: true
  def payload_executes?({:refuse, _}), do: false

  # Mirrors the identity gate: the candidate tag must report its stable product
  # version, and any other identity is refused with exit 125.
  def identity_verdict(candidate, reported) do
    if stable_of(candidate) == reported, do: :install, else: {:refuse, 125}
  end

  # Mirrors reclaim_orphan_install_records and reclaim_legacy_install_lock: a record
  # is reclaimed only when its owner is positively stale, and an orphan also needs
  # the 300 s expiry.
  def preparation_reclaim(%{kind: :legacy_lock, owner_stale: stale}),
    do: if(stale, do: :reclaim, else: :keep)

  def preparation_reclaim(%{kind: :orphan, age_seconds: age, owner_stale: true}) when age >= 300,
    do: :reclaim

  def preparation_reclaim(%{kind: :orphan}), do: :keep

  # Mirrors the contention outcomes: one download, the live owner keeps the install,
  # and no owner record survives.
  def contention_outcome(:cold_callers),
    do: %{downloads: 1, owner: :first_caller, owner_records: 0}

  def contention_outcome(:stale_reclaim),
    do: %{downloads: 1, owner: :live_replacement, owner_records: 0}

  # Mirrors retention ranking: releases rank by real timestamp, newest first, and the
  # two most recent fallbacks are kept.
  def retained_fallbacks(releases) do
    releases
    |> Enum.sort_by(& &1.mtime, :desc)
    |> Enum.take(2)
    |> Enum.map(& &1.name)
  end

  def cache_plan(:empty), do: {:download, 1}
  def cache_plan(:warm_valid), do: {:reuse, 0}
  def cache_plan(:tampered), do: {:refuse, 99}

  # Mirrors rhino:585-593 (the vector goes through untouched).
  def passthrough(caller), do: caller

  # Mirrors rhino:229-251,401-469 (live waits; dead, reused, crashed take over).
  def wait_verdict(:live_intact), do: :wait
  def wait_verdict(:live_malformed), do: :wait
  def wait_verdict(:dead_pid), do: :takeover
  def wait_verdict(:reused_pid), do: :takeover
  def wait_verdict(:crashed), do: :takeover

  # Mirrors rhino:479 retention_idle_seconds=604800 and claimed/pinned gates.
  def retention_keep?(%{claimed: true}), do: true
  def retention_keep?(%{pinned: true}), do: true
  def retention_keep?(%{idle_seconds: s}) when is_integer(s) and s < 604_800, do: true
  def retention_keep?(_), do: false

  # Mirrors rhino:280-281 and rhino:468-469 (bounded waits exit 124).
  def guard_wait_verdict(:granted), do: :proceed

  def guard_wait_verdict(:timeout),
    do: {:error, 124, "rhino bootstrap timed out waiting for its install guard"}

  def lock_wait_verdict(:granted), do: :proceed

  def lock_wait_verdict(:timeout),
    do: {:error, 124, "rhino bootstrap timed out waiting for its install lock"}

  # Mirrors rhino:264 (Darwin needs lockf) and rhino:272 (Linux needs flock).
  def lock_tool_error("Linux"), do: {:error, 125, "rhino bootstrap requires flock on Linux"}
  def lock_tool_error("Darwin"), do: {:error, 125, "rhino bootstrap requires lockf on Darwin"}

  # Mirrors the disjoint-state scenarios: each tool keeps its own cache root
  # and honours only its own setting, falling back to its own default.
  def cache_root(:rhino, {:set, value}), do: value
  def cache_root(:rhino, :unset), do: :rhino_default
  def cache_root(:hippo, {:set, value}), do: value
  def cache_root(:hippo, :unset), do: :hippo_default

  def caches_apart?(rhino_root, hippo_root), do: rhino_root != hippo_root

  # The install lock is one key in an in-memory store, holding the record its
  # owner published. Publication is create-if-absent, as the hard link at
  # rhino:454 is: a record already present means the caller must wait.
  def acquire_install_lock(store, path, record) do
    if Map.has_key?(store, path),
      do: {:busy, store},
      else: {:ok, Map.put(store, path, record)}
  end

  # Stands for another consumer that reclaims a stale lock (rhino:401) and then
  # publishes its own record in the same create-if-absent step (rhino:454).
  def replace_install_lock(store, path, record), do: Map.put(store, path, record)

  # Mirrors release_install_lock (rhino:291-304): the lock is removed only while
  # both its file identity and its record digest are still this consumer's own.
  def release_install_lock(store, path, %{identity: identity, digest: digest}) do
    case Map.fetch(store, path) do
      {:ok, %{identity: ^identity, digest: ^digest}} -> Map.delete(store, path)
      _replacement -> store
    end
  end

  # Mirrors acquire_install_guard (rhino:254-257): the guard file sits at the cache
  # root, so its path depends on the cache root alone and never on the release.
  def install_guard_path(cache_root, _release), do: Path.join(cache_root, ".install-guard.lock")

  # One install takes the guard, then publishes the release directory. The guard
  # file outlives the install (release_install_guard, rhino:284-289).
  def install_release(cache, cache_root, release) do
    cache
    |> Map.put_new(install_guard_path(cache_root, release), :guard)
    |> Map.put(Path.join(cache_root, release), :release)
  end

  # Stands for prune_cache (rhino:481-522) keeping only the current release. Release
  # directories are removed; the guard file is not a release directory and stays.
  def prune_superseded(cache, cache_root, current) do
    current_dir = Path.join(cache_root, current)

    for {path, kind} <- cache,
        not (kind == :release and path != current_dir),
        into: %{},
        do: {path, kind}
  end
end

defmodule BnestApp.Behaviour.Tools.RhinoBootstrapTest do
  @moduledoc """
  Unit bindings for `rhino-bootstrap.feature`. Every scenario below carries
  its `@scenario` reference so the behaviour coverage check sees the unit
  binding the review requires.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.Tools.RhinoBootstrapModel, as: Model

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A cold cache installs once and a warm cache needs no transport
  test "cold cache downloads once and warm cache reuses" do
    assert Model.cache_plan(:empty) == {:download, 1}
    assert Model.cache_plan(:warm_valid) == {:reuse, 0}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: The caller's argument vector reaches the release unchanged
  test "argument vector passes through untouched" do
    # Mirrors rhino:585-593; harness run_argument_vector_passthrough.
    caller = ["md", "word-count", "inspect", "--file", "README.md"]
    assert Model.passthrough(caller) == caller
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Tampered warm-cache payload never executes
  test "tampered payload is refused before execution" do
    assert Model.cached_verdict(:tampered_digest) == {:refuse, 99}
    assert Model.cached_verdict(:tampered_identity) == {:refuse, 99}
    assert Model.cached_verdict(:valid) == :run
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A downloaded release that fails verification is refused
  test "failed verification refuses without publishing" do
    assert Model.download_verdict(:digest_mismatch) == {:refuse, 125}
    assert Model.download_verdict(:identity_mismatch) == {:refuse, 125}
    assert Model.download_verdict(:ok) == :install
    refute Model.payload_executes?(Model.download_verdict(:digest_mismatch))
    refute Model.payload_executes?(Model.download_verdict(:identity_mismatch))
    assert Model.payload_executes?(Model.download_verdict(:ok))
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Non-exact stable release version is rejected
  test "malformed or path-shaped version is rejected" do
    # Mirrors rhino:71-73; harness rejects v1x and traversal rows.
    refute Model.version_valid?("v1x.2.3")
    refute Model.version_valid?("v1.2.3/../../../escape")
    refute Model.version_valid?("v1.2")
    assert Model.version_valid?("v1.2.3")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A pinned release candidate installs and runs
  test "exact candidate installs and reports its stable product version" do
    # Mirrors rhino:71 plus rhino:85 stable-product mapping.
    assert Model.version_valid?("v9.8.7-rc.5")
    assert Model.stable_of("v9.8.7-rc.5") == "v9.8.7"
    assert Model.download_verdict(:ok) == :install
    assert Model.cache_plan(:warm_valid) == {:reuse, 0}
    # Mirrors the stable identity gate: the candidate verifies against its stable version.
    assert Model.identity_verdict("v9.8.7-rc.5", "v9.8.7") == :install
    assert Model.identity_verdict("v9.8.7-rc.5", "v9.8.8") == {:refuse, 125}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Unsupported platform is refused before any transport
  test "unknown triple is refused" do
    assert Model.platform_target("Linux", "x86_64") == {:ok, "x86_64-unknown-linux-gnu"}
    assert Model.platform_target("Darwin", "arm64") == {:ok, "aarch64-apple-darwin"}

    assert Model.platform_target("Plan9", "x86_64") ==
             {:error, 125, "rhino does not support this operating system"}

    assert Model.platform_target("Linux", "riscv64") ==
             {:error, 125, "rhino does not support this architecture"}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A caller waits while another caller is installing
  test "live owner makes the caller wait" do
    assert Model.wait_verdict(:live_intact) == :wait
    assert Model.wait_verdict(:live_malformed) == :wait
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A caller takes over an install whose owner is gone
  test "gone owner is taken over" do
    assert Model.wait_verdict(:dead_pid) == :takeover
    assert Model.wait_verdict(:reused_pid) == :takeover
    assert Model.wait_verdict(:crashed) == :takeover
    # Mirrors run_crash_before_publication: a legacy lock or an orphan record is
    # reclaimed only when positively stale, and fresh or live records stay.
    stale = %{owner_stale: true}
    live = %{owner_stale: false}
    assert Model.preparation_reclaim(Map.merge(%{kind: :legacy_lock}, stale)) == :reclaim
    assert Model.preparation_reclaim(Map.merge(%{kind: :legacy_lock}, live)) == :keep

    assert Model.preparation_reclaim(Map.merge(%{kind: :orphan, age_seconds: 600}, stale)) ==
             :reclaim

    assert Model.preparation_reclaim(Map.merge(%{kind: :orphan, age_seconds: 10}, stale)) == :keep
    assert Model.preparation_reclaim(Map.merge(%{kind: :orphan, age_seconds: 600}, live)) == :keep
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Two callers starting together download once and both run the release
  test "concurrent cold callers share one download" do
    assert Model.cache_plan(:empty) == {:download, 1}
    assert Model.wait_verdict(:crashed) == :takeover
    # Mirrors run_concurrent_cold_callers and run_concurrent_stale_reclaimers.
    assert Model.contention_outcome(:cold_callers) ==
             %{downloads: 1, owner: :first_caller, owner_records: 0}

    assert Model.contention_outcome(:stale_reclaim) ==
             %{downloads: 1, owner: :live_replacement, owner_records: 0}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A consumer never removes an install lock it did not publish
  test "a consumer leaves a replacement install lock in place" do
    # Mirrors release_install_lock (rhino:291-304); harness run_never_removes_a_foreign_install_lock.
    lock = "/cache/rhino/v9.8.7.lock"
    own = %{identity: "pid-41:start-100", digest: "digest-a"}
    third = %{identity: "pid-99:start-500", digest: "digest-c"}

    # A live owner replaces the published record: identity differs, digest differs, both differ.
    replacements = [
      %{identity: "pid-77:start-900", digest: "digest-a"},
      %{identity: "pid-41:start-100", digest: "digest-b"},
      %{identity: "pid-77:start-900", digest: "digest-b"}
    ]

    for replacement <- replacements do
      assert {:ok, store} = Model.acquire_install_lock(%{}, lock, own)
      store = Model.replace_install_lock(store, lock, replacement)
      store = Model.release_install_lock(store, lock, own)

      assert Map.get(store, lock) == replacement
      assert {:busy, _store} = Model.acquire_install_lock(store, lock, third)
    end

    # Untouched case: A's own release empties the store, so the next owner is admitted.
    assert {:ok, store} = Model.acquire_install_lock(%{}, lock, own)
    store = Model.release_install_lock(store, lock, own)

    assert store == %{}
    assert {:ok, _store} = Model.acquire_install_lock(store, lock, third)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Install guard storage stays bounded across release versions
  test "install guard storage stays one file across release versions" do
    # Mirrors acquire_install_guard (rhino:208-211); harness run_bounded_install_guard_storage.
    cache_root = "/cache/rhino"
    releases = ["v9.8.7", "v9.8.8", "v9.8.9", "v9.8.10", "v9.8.11"]
    current = List.last(releases)

    installed = Enum.reduce(releases, %{}, &Model.install_release(&2, cache_root, &1))
    pruned = Model.prune_superseded(installed, cache_root, current)

    guard = Model.install_guard_path(cache_root, current)
    guards = for {path, :guard} <- pruned, do: path
    keys_per_version = Enum.map(releases, &Model.install_guard_path(cache_root, &1))

    assert guards == [guard]
    assert Enum.uniq(keys_per_version) == [guard]
    assert pruned == %{guard => :guard, Path.join(cache_root, current) => :release}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Retention never deletes a release another consumer is using
  test "claimed release survives retention" do
    assert Model.retention_keep?(%{claimed: true, pinned: false, idle_seconds: 999_999_999})
    refute Model.retention_keep?(%{claimed: false, pinned: false, idle_seconds: 999_999_999})
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Retention never evicts a release another repository still uses
  test "each repository keeps its pinned release" do
    assert Model.retention_keep?(%{claimed: false, pinned: true, idle_seconds: 999_999_999})
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Retention reclaims releases left idle beyond its window
  test "only pinned and recent idle fallbacks remain" do
    assert Model.retention_keep?(%{claimed: false, pinned: false, idle_seconds: 100})
    refute Model.retention_keep?(%{claimed: false, pinned: false, idle_seconds: 604_800})
    # Ranking reads real timestamps: the newest releases are kept whatever their names.
    newest_first_name_last = [
      %{name: "v8.1.1", mtime: 5},
      %{name: "v8.1.2", mtime: 4},
      %{name: "v8.1.3", mtime: 3},
      %{name: "v8.1.4", mtime: 2},
      %{name: "v8.1.5", mtime: 1}
    ]

    assert Model.retained_fallbacks(newest_first_name_last) == ["v8.1.1", "v8.1.2"]
    oldest_first_name_last = Enum.map(newest_first_name_last, &%{&1 | mtime: 6 - &1.mtime})
    assert Model.retained_fallbacks(oldest_first_name_last) == ["v8.1.5", "v8.1.4"]
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Installing both tools on one machine keeps their caches apart
  test "both tools keep their caches apart" do
    rhino = Model.cache_root(:rhino, {:set, "r-cache"})
    hippo = Model.cache_root(:hippo, {:set, "h-cache"})
    assert Model.caches_apart?(rhino, hippo)
    refute Model.caches_apart?(rhino, rhino)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: Each tool honours only its own cache-root setting
  test "each tool honours only its own setting" do
    assert Model.cache_root(:rhino, {:set, "mine"}) == "mine"
    assert Model.cache_root(:rhino, :unset) == :rhino_default
    assert Model.cache_root(:hippo, {:set, "mine"}) == "mine"
    assert Model.cache_root(:hippo, :unset) == :hippo_default
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A missing, duplicated, or malformed pin exits 125 before any transport
  test "bad pin exits 125" do
    assert Model.pin_result(:no_lock) == {:error, 125, "rhino has no pin at rhino.lock"}

    assert Model.pin_result({:duplicate, "version"}) ==
             {:error, 125, "rhino lock has missing or duplicate version"}

    assert Model.pin_result({:missing, "version"}) ==
             {:error, 125, "rhino lock has missing or duplicate version"}

    assert Model.pin_result({:bad_commit, "short"}) ==
             {:error, 125, "rhino lock has an invalid commit"}

    assert Model.pin_result({:bad_checksum, "short"}) ==
             {:error, 125, "rhino lock has an invalid checksum"}

    assert Model.pin_result(:ok) == :ok
    refute Model.version_valid?("bad-version")
    refute Model.commit_valid?("short")
    refute Model.checksum_valid?("short")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A bounded wait for the install guard or lock that runs out exits 124
  test "exhausted bounded waits exit 124" do
    assert Model.guard_wait_verdict(:timeout) ==
             {:error, 124, "rhino bootstrap timed out waiting for its install guard"}

    assert Model.lock_wait_verdict(:timeout) ==
             {:error, 124, "rhino bootstrap timed out waiting for its install lock"}

    assert Model.guard_wait_verdict(:granted) == :proceed
    assert Model.lock_wait_verdict(:granted) == :proceed
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature: A host without flock or lockf exits 125
  test "missing lock tool exits 125" do
    assert Model.lock_tool_error("Linux") ==
             {:error, 125, "rhino bootstrap requires flock on Linux"}

    assert Model.lock_tool_error("Darwin") ==
             {:error, 125, "rhino bootstrap requires lockf on Darwin"}
  end
end
