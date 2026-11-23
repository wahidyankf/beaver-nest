defmodule BnestApp.Behaviour.OperatorCommandsIntegrationTest do
  @moduledoc """
  Integration tests for the `operator_commands.feature` adapter. The bound
  scenarios run the real implementation against an isolated run base: the
  Storage and Identity facades over real SQLite, the task `run/1` entry
  points with bad options, and the Node cleanup script as a child process.
  Exempt scenarios need no marker here; their `@e2e-exempt` tag is the
  integration proof the review records.
  """

  # The adapters install Storage ports, change the application environment
  # and run child processes, all global to the VM, so scenarios run
  # sequentially.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.OperatorCommands.IntegrationAdapter, as: Adapter
  alias BnestApp.Behaviour.OperatorCommandsModel, as: Model

  defp context, do: Adapter.install(%{})

  # @scenario specs/apps/bnest/app-be/behaviours/operator_commands.feature: mix bnest.storage.purge_test_data verifies or purges verified legacy test data
  test "purge verifies or purges the generation and refuses anything else" do
    for {arguments, line, state} <- [
          {"--generation gen --dry-run", "legacy test data verified records=2 recovery_sources=1",
           "kept"},
          {"--generation gen", "legacy test data purged records=2 recovery_sources=1", "removed"},
          {"--generation other", "legacy test data cleanup refused: generation_mismatch", "kept"},
          {"--dry-run",
           "usage: mix bnest.storage.purge_test_data --generation <generation> [--dry-run]",
           "kept"}
        ] do
      context()
      |> Adapter.seed_generation()
      |> Adapter.run_purge(arguments)
      |> Adapter.assert_report(line)
      |> Adapter.assert_legacy_state(state)
    end
  end

  # @scenario specs/apps/bnest/app-be/behaviours/operator_commands.feature: mix bnest.schema.audit prints one pass or fail line per record type
  test "audit prints one line per record type and refuses a bad root" do
    for {arguments, line, outcome} <- [
          {"(default root)", "chat:v1 pass", "exits 0"},
          {"(other root)", "chat:v1 fail", "raises schema audit failed"},
          {"(refused root)", "schema audit refused: unsupported_root",
           "raises schema audit refused: unsupported_root"}
        ] do
      context()
      |> Adapter.seed_audit_roots()
      |> Adapter.run_audit(arguments)
      |> Adapter.assert_report(line)
      |> Adapter.assert_audit_outcome(outcome)
    end
  end

  # @scenario specs/apps/bnest/app-be/behaviours/operator_commands.feature: mix bnest.identity.benchmark prints the Argon2id cost and a timing class, never a secret
  test "benchmark prints the cost and the timing class, never a secret" do
    for timing <- ["999 ms Argon2id", "1000 ms Argon2id"] do
      context = context() |> Adapter.seed_timing(timing) |> Adapter.run_benchmark()
      line = context.operator.report
      cost = context.operator.cost

      assert line ==
               "argon2id memory_kib=#{cost[:memory_kib]} iterations=#{cost[:time_cost]} " <>
                 "parallelism=#{cost[:parallelism]} timing_class=#{timing_class(line)}"

      refute line =~ ~r/\$argon2id|\$2[aby]\$|[0-9a-f]{32,}/i
    end

    context = context() |> Adapter.seed_timing("not Argon2id") |> Adapter.run_benchmark()

    assert context.operator.report == "configured password hasher did not produce Argon2id"
  end

  # @scenario specs/apps/bnest/app-be/behaviours/operator_commands.feature: The storage tasks refuse unknown options with their usage line
  test "storage task runs refuse unknown options with their usage line" do
    for {task, arguments, usage} <- [
          {"bnest.storage.migrate", "--unknown", Model.usage(:migrate)},
          {"bnest.storage.migrate", "stray", Model.usage(:migrate)},
          {"bnest.storage.relocate", "--unknown", Model.usage(:relocate)},
          {"bnest.storage.relocate", "stray", Model.usage(:relocate)},
          {"bnest.storage.retire", "--generation gen", Model.usage(:retire)},
          {"bnest.storage.retire", "--root root", Model.usage(:retire)},
          {"purge_test_data", "--dry-run", Model.usage(:purge_test_data)},
          {"bnest.schema.audit", "stray", Model.usage(:schema_audit)}
        ] do
      context()
      |> Adapter.seed_isolated_root()
      |> Adapter.run_storage_task(task, arguments)
      |> Adapter.assert_refusal(usage)
    end
  end

  # @scenario specs/apps/bnest/app-be/behaviours/operator_commands.feature: node tools/test-data-cleanup.mjs removes only stale marked test runs and reports the counts
  test "cleanup removes only stale marked runs and reports the counts" do
    for {setup, line} <- [
          {"a stale marked run with a dead owner", "test data cleanup: removed=1 retained=0"},
          {"a young marked run", "test data cleanup: removed=0 retained=1"},
          {"an unmarked directory", "test data cleanup: removed=0 retained=1"},
          {"a stale marked run with a live owner", "test data cleanup: removed=0 retained=1"},
          {"a stale legacy run", "test data cleanup: removed=1 retained=0"},
          {"a symlinked run", "test data cleanup: removed=0 retained=0"}
        ] do
      context()
      |> Adapter.seed_test_home(setup)
      |> Adapter.run_cleanup()
      |> Adapter.assert_cleanup_line(line)
    end
  end

  # @scenario specs/apps/bnest/app-be/behaviours/operator_commands.feature: Test-data cleanup refuses bad arguments and negative hours
  test "cleanup refuses bad arguments and negative hours" do
    for {arguments, refusal} <- [
          {"--unknown", "usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]"},
          {"--older-than-hours",
           "usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]"},
          {"extra", "usage: node tools/test-data-cleanup.mjs [--older-than-hours <hours>]"},
          {"--older-than-hours -1", "hours must be non-negative"},
          {"--older-than-hours lot", "hours must be non-negative"}
        ] do
      context()
      |> Adapter.seed_test_home("a stale marked run with a dead owner")
      |> Adapter.run_cleanup_with(arguments)
      |> Adapter.assert_cleanup_refusal(refusal)
    end
  end

  defp timing_class(line) do
    ["under-one-second", "one-second-or-more"]
    |> Enum.find(fn class -> String.ends_with?(line, "timing_class=#{class}") end)
    |> case do
      nil -> raise "the benchmark line names no timing class: #{inspect(line)}"
      class -> class
    end
  end
end
