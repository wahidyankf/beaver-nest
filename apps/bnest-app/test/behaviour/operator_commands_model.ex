defmodule BnestApp.Behaviour.OperatorCommandsModel do
  @moduledoc """
  Shared expectations for `specs/apps/bnest/app-be/behaviours/operator_commands.feature`.

  Both behaviour layers execute the scenarios through this model. The unit
  adapter feeds it the scenario's own data over the in-memory doubles, which
  proves the scenario logic; the integration adapter feeds it values read back
  from an isolated run base with the real adapters, which proves the
  implementation. The Node suites in `apps/bnest-app/tools/test-data-cleanup.test.mjs`
  prove the same contracts against the real script with temporary trees.
  """

  @usage %{
    migrate: "usage: mix bnest.storage.migrate [--root <flat-root>] [--activate]",
    relocate: "usage: mix bnest.storage.relocate [--destination <directory>]",
    retire:
      "usage: mix bnest.storage.retire --root <flat-root> --generation <generation> [--dry-run]",
    purge_test_data:
      "usage: mix bnest.storage.purge_test_data --generation <generation> [--dry-run]",
    schema_audit: "usage: mix bnest.schema.audit [--root <runtime-root>]",
    cleanup: "usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]"
  }

  @doc "The reviewed usage line for an operator task."
  def usage(task), do: Map.fetch!(@usage, task)

  @doc "The reviewed legacy test-data line for a purge result."
  def purge_line(dry_run?, {:ok, counts}) do
    action = if dry_run?, do: "verified", else: "purged"

    "legacy test data #{action} records=#{counts.records} recovery_sources=#{counts.recovery_sources}"
  end

  @doc "The reviewed audit line for one record-type result."
  def audit_line(record_type, schema_version, result),
    do: "#{record_type}:v#{schema_version} #{result}"

  @doc "The reviewed benchmark line for a cost and a measured time."
  def benchmark_line(options, elapsed_ms) do
    timing = if elapsed_ms < 1_000, do: "under-one-second", else: "one-second-or-more"

    "argon2id memory_kib=#{options[:memory_kib]} iterations=#{options[:time_cost]} " <>
      "parallelism=#{options[:parallelism]} timing_class=#{timing}"
  end

  @doc "True when a cleanup refusal names the usage line rather than the hours rule."
  def usage_refusal?(message), do: message == Map.fetch!(@usage, :cleanup)

  @doc "True when a cleanup refusal names the hours rule."
  def hours_refusal?(message), do: message == "hours must be non-negative"

  @cleanup_setups %{
    "a stale marked run with a dead owner" => {1, 0},
    "a young marked run" => {0, 1},
    "an unmarked directory" => {0, 1},
    "a stale marked run with a live owner" => {0, 1},
    "a stale legacy run" => {1, 0},
    "a symlinked run" => {0, 0}
  }

  @doc "The reviewed `{removed, retained}` counts for a cleanup setup."
  def cleanup_expectation(setup), do: Map.fetch!(@cleanup_setups, setup)

  @doc "The reviewed cleanup line for `{removed, retained}` counts."
  def cleanup_line(removed, retained),
    do: "test data cleanup: removed=#{removed} retained=#{retained}"

  @doc """
  Mirrors the reviewed `parseOlderThanHours` contract of
  `tools/test-data-cleanup.mjs`: the default threshold, the flag form, and
  the usage and hours refusals.
  """
  def parse_cleanup_args([]), do: {:ok, 24}

  def parse_cleanup_args(["--older-than-hours", value]) do
    # Mirrors JavaScript's `Number`: any finite non-negative number passes, so
    # `2.5` counts as a threshold exactly as the script reads it.
    case Float.parse(value) do
      {hours, ""} when hours >= 0 -> {:ok, hours}
      _ -> {:error, "hours must be non-negative"}
    end
  end

  def parse_cleanup_args(_arguments),
    do: {:error, "usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]"}
end
