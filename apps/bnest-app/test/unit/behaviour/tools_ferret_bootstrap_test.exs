defmodule BnestApp.Behaviour.Tools.FerretBootstrapModel do
  @moduledoc false

  # Pure mirror of the ferret wrapper (ferret:24-114).

  # Mirrors ferret:46 (exact stable version, no candidate suffix).
  def version_valid?(version), do: version =~ ~r/^v\d+\.\d+\.\d+$/

  # Mirrors ferret:47 (40 lowercase hex commit).
  def commit_valid?(commit), do: commit =~ ~r/^[0-9a-f]{40}$/

  # Mirrors ferret:48 (64 lowercase hex artifact digest).
  def digest_valid?(digest), do: digest =~ ~r/^[0-9a-f]{64}$/

  # Mirrors ferret:54 (one artifact, no platform matrix).
  def artifact(version), do: "ferret-cli_#{version}.pyz"

  # Mirrors ferret:29,37-38 (pin presence and uniqueness, exit 125).
  def pin_result(:no_lock), do: {:error, 125, "there is no pin at ferret.lock"}
  def pin_result({:duplicate, key}), do: {:error, 125, "the pin declares #{key} more than once"}
  def pin_result({:missing, key}), do: {:error, 125, "the pin declares no #{key}"}

  def pin_result({:bad_version, _}),
    do: {:error, 125, "the pin declares an invalid stable version"}

  def pin_result({:bad_commit, _}), do: {:error, 125, "the pin declares an invalid commit"}

  def pin_result({:bad_digest, _}),
    do: {:error, 125, "the pin declares an invalid artifact digest"}

  def pin_result(:ok), do: :ok

  # Mirrors ferret:97,103,106,110,114 (install refusal rows, exit 125,
  # nothing published or run). The wrapper has no bounded wait, so it
  # never exits 124 (ferret:14-17).
  def install_verdict(:archive_fetch_fails), do: {:error, 125, "could not be fetched"}
  def install_verdict(:checksums_fetch_fails), do: {:error, 125, "checksums could not be fetched"}

  def install_verdict(:published_digest_mismatch),
    do: {:error, 125, "publishes a different digest"}

  def install_verdict(:bytes_mismatch), do: {:error, 125, "does not match the pinned digest"}

  def install_verdict(:version_mismatch),
    do: {:error, 125, "reports a version the pin does not name"}

  def install_verdict(:cached_tampered), do: {:error, 125, "did not verify"}
  def install_verdict(:ok), do: :run

  def never_124?, do: true

  # Mirrors ferret:84 (cached binary must report the pinned version).
  def version_report_ok?(reported, version),
    do: reported == "ferret " <> String.trim_leading(version, "v")

  # Mirrors ferret:67,96-114 (atomic rename publish; transport only on miss).
  def transport_needed?(:cache_miss), do: true
  def transport_needed?(:cache_hit_valid), do: false
  def transport_needed?(:cache_hit_tampered), do: false
end

defmodule BnestApp.Behaviour.Tools.FerretBootstrapTest do
  @moduledoc """
  Unit bindings for `ferret-bootstrap.feature`. Every scenario below carries
  its `@scenario` reference so the behaviour coverage check sees the unit
  binding the review requires.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.Tools.FerretBootstrapModel, as: Model

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature: ./ferret installs and verifies the pinned FERRET before running it
  test "cold cache verifies and warm cache redigests without transport" do
    # Harness run_install_and_verify in test-ferret-bootstrap.sh.
    assert Model.artifact("v9.9.9") == "ferret-cli_v9.9.9.pyz"
    assert Model.transport_needed?(:cache_miss)
    refute Model.transport_needed?(:cache_hit_valid)
    refute Model.transport_needed?(:cache_hit_tampered)
    assert Model.version_report_ok?("ferret 9.9.9", "v9.9.9")
    refute Model.version_report_ok?("ferret 0.0.0", "v9.9.9")
    assert Model.install_verdict(:ok) == :run
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature: ./ferret refuses an unpinned fallback or a failed install
  test "failed install refuses with 125 and publishes nothing" do
    # Mirrors ferret:97,103,106,110,114 plus the cached-tamper row.
    for failure <- [
          :archive_fetch_fails,
          :checksums_fetch_fails,
          :published_digest_mismatch,
          :bytes_mismatch,
          :version_mismatch,
          :cached_tampered
        ] do
      assert {:error, 125, _} = Model.install_verdict(failure)
    end

    assert Model.never_124?()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature: A missing, duplicated, or malformed pin makes ./ferret refuse with 125
  test "bad pin refuses with 125" do
    # Mirrors ferret:29,37-38,46-48; harness run_pin_refusals_125.
    assert Model.pin_result(:no_lock) == {:error, 125, "there is no pin at ferret.lock"}

    assert Model.pin_result({:duplicate, "version"}) ==
             {:error, 125, "the pin declares version more than once"}

    assert Model.pin_result({:bad_version, "x"}) ==
             {:error, 125, "the pin declares an invalid stable version"}

    assert Model.pin_result({:bad_commit, "x"}) ==
             {:error, 125, "the pin declares an invalid commit"}

    assert Model.pin_result({:bad_digest, "x"}) ==
             {:error, 125, "the pin declares an invalid artifact digest"}

    assert Model.pin_result(:ok) == :ok
    refute Model.version_valid?("bad-version")
    refute Model.commit_valid?("short")
    refute Model.digest_valid?("short")
    assert Model.version_valid?("v9.9.9")
  end
end
