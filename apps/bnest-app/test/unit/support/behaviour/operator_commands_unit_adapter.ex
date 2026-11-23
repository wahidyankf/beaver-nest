defmodule BnestApp.Behaviour.OperatorCommands.UnitAdapter do
  @moduledoc """
  The unit layer's adapter for `operator_commands.feature`. It drives the
  production Mix task entry points that are pure (`parse!/1`, the report-line
  builders) and the Storage and Identity facades over the in-memory doubles,
  so it proves the scenario logic without touching a file, a socket, or a
  booted application. The Node scenarios prove the same contracts through
  the reviewed model below, and the integration adapter runs the real
  implementations. Only the integration adapter reads real files and runs
  real child processes.
  """

  alias BnestApp.Behaviour.OperatorCommandsModel, as: Model
  alias BnestApp.Storage
  alias BnestApp.Test.InMemory.StoragePorts
  alias Mix.Tasks.Bnest.Identity.Benchmark, as: BenchmarkTask
  alias Mix.Tasks.Bnest.Schema.Audit, as: AuditTask
  alias Mix.Tasks.Bnest.Storage.Migrate, as: MigrateTask
  alias Mix.Tasks.Bnest.Storage.PurgeTestData, as: PurgeTask
  alias Mix.Tasks.Bnest.Storage.Relocate, as: RelocateTask
  alias Mix.Tasks.Bnest.Storage.Retire, as: RetireTask

  @generation "gen"

  @doc "Installs the operator state in the scenario context."
  def install(context) do
    previous_shell = Mix.shell()

    context
    |> Map.put(:operator_adapter, __MODULE__)
    |> Map.put(:operator, %{shell: previous_shell})
  end

  @doc "Nothing to release: the scenario context is discarded with the test."
  def release(context), do: context

  defp put_operator(context, patch),
    do: %{context | operator: Map.merge(context.operator, patch)}

  defp install_storage_ports!(context) do
    # The agent is shared by every row of one scenario: each Given only
    # re-seeds the canned answers, and the first Given starts it.
    if is_nil(GenServer.whereis(StoragePorts)) do
      previous = StoragePorts.install()
      ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
    end

    put_operator(context, %{storage_ports?: true})
  end

  # mix bnest.storage.purge_test_data (BN-CLI-21).

  def seed_generation(context) do
    context = install_storage_ports!(context)
    StoragePorts.put(:purge, {:ok, %{records: 2, recovery_sources: 1}})
    put_operator(context, %{generation: @generation})
  end

  def run_purge(context, arguments) do
    argv = String.split(arguments, " ", trim: true)

    purge_report =
      try do
        options = PurgeTask.parse!(argv)
        purge(context, options)
      rescue
        error in Mix.Error -> {:raised, Exception.message(error), nil}
      end

    put_operator(context, %{purge_report: purge_report})
  end

  defp purge(context, %{generation: generation, dry_run?: dry_run?}) do
    if generation != context.operator.generation do
      StoragePorts.put(:purge, {:error, :generation_mismatch})
    end

    case Storage.purge_test_data(generation, dry_run?) do
      {:ok, counts} ->
        line = PurgeTask.report_line(dry_run?, {:ok, counts})
        capture_print(fn -> PurgeTask.print_report(dry_run?, {:ok, counts}) end)
        {:printed, line, dry_run?}

      {:error, reason} ->
        message =
          try do
            PurgeTask.refuse(reason)
          rescue
            error in Mix.Error -> Exception.message(error)
          end

        {:raised, message, dry_run?}
    end
  end

  def assert_report(context, expected) do
    report =
      case context.operator do
        %{purge_report: {_kind, line, _dry?}} -> line
        %{audit_line: line} -> line
        %{report: line} -> line
      end

    unless report == expected,
      do: raise("the task reported #{inspect(report)}, expected #{inspect(expected)}")

    context
  end

  def assert_legacy_state(context, "kept") do
    calls = StoragePorts.calls()

    case context.operator.purge_report do
      {:printed, _line, true} ->
        unless {:purge_test_data, @generation, true} in calls,
          do: raise("a dry run did not verify the generation: #{inspect(calls)}")

      {:raised, _message, _dry?} ->
        :ok
    end

    context
  end

  def assert_legacy_state(context, "removed") do
    calls = StoragePorts.calls()

    unless {:purge_test_data, @generation, false} in calls,
      do: raise("no purge of the generation ran: #{inspect(calls)}")

    context
  end

  # mix bnest.schema.audit (BN-CLI-22).

  def seed_audit_roots(context) do
    context
    |> install_storage_ports!()
    |> put_operator(%{audit_roots: %{default: "default-root", other: "other-root"}})
  end

  def run_audit(context, arguments) do
    {root, canned} =
      case arguments do
        "(default root)" ->
          {"default-root",
           {:ok, [%{"recordType" => "chat", "schemaVersion" => 1, "result" => "pass"}]}}

        "(other root)" ->
          {"other-root",
           {:ok, [%{"recordType" => "chat", "schemaVersion" => 1, "result" => "fail"}]}}

        "(refused root)" ->
          {"refused-root", {:error, :unsupported_root}}
      end

    StoragePorts.put(:audit, canned)

    outcome = audit_outcome(root)

    line =
      case outcome do
        {:ok, audit_line, _check} -> audit_line
        {:error, {:raised, message}} -> message
      end

    put_operator(context, %{audit_outcome: outcome, audit_line: line})
  end

  defp audit_outcome(root) do
    case Storage.audit_schema(root) do
      {:ok, results} ->
        lines = Enum.map(results, &AuditTask.format_result/1)
        capture_print(fn -> AuditTask.print_report(results) end)

        check =
          try do
            AuditTask.check!(results)
          rescue
            error in Mix.Error -> {:raised, Exception.message(error)}
          end

        {:ok, hd(lines), check}

      {:error, reason} ->
        message =
          try do
            AuditTask.refuse(reason)
          rescue
            error in Mix.Error -> {:raised, Exception.message(error)}
          end

        {:error, message}
    end
  end

  def assert_audit_outcome(context, expected) do
    actual =
      case context.operator.audit_outcome do
        {:ok, _line, :ok} -> "exits 0"
        {:ok, _line, {:raised, message}} -> "raises #{message}"
        {:error, {:raised, message}} -> "raises #{message}"
      end

    unless actual == expected,
      do: raise("the audit #{inspect(actual)}, expected #{inspect(expected)}")

    context
  end

  # mix bnest.identity.benchmark (BN-CLI-23).

  def seed_timing(context, timing) do
    benchmark =
      case timing do
        "999 ms Argon2id" -> {:ok, 999}
        "1000 ms Argon2id" -> {:ok, 1_000}
        "not Argon2id" -> {:error, :not_argon2id}
      end

    cost = [memory_kib: 32_768, time_cost: 2, parallelism: 1]
    previous_cost = Application.get_env(:bnest_app, :argon2)
    previous_benchmark = Application.get_env(:bnest_app, :in_memory_benchmark)
    Application.put_env(:bnest_app, :argon2, cost)
    Application.put_env(:bnest_app, :in_memory_benchmark, benchmark)

    ExUnit.Callbacks.on_exit(fn ->
      if previous_cost == nil,
        do: Application.delete_env(:bnest_app, :argon2),
        else: Application.put_env(:bnest_app, :argon2, previous_cost)

      if previous_benchmark == nil,
        do: Application.delete_env(:bnest_app, :in_memory_benchmark),
        else: Application.put_env(:bnest_app, :in_memory_benchmark, previous_benchmark)
    end)

    put_operator(context, %{timing: timing, cost: cost, benchmark: benchmark})
  end

  def run_benchmark(context) do
    %{cost: cost, benchmark: benchmark} = context.operator

    report =
      case benchmark do
        {:ok, elapsed_ms} ->
          line = BenchmarkTask.report_line(cost, elapsed_ms)
          capture_print(fn -> Mix.shell().info(line) end)

          unless line == Model.benchmark_line(cost, elapsed_ms),
            do: raise("the benchmark line drifts from the reviewed wording")

          if line =~ ~r/\$argon2|password|hash/i,
            do: raise("the benchmark line carries a secret: #{inspect(line)}")

          line

        {:error, _reason} ->
          "configured password hasher did not produce Argon2id"
      end

    case BnestApp.Identity.benchmark_hasher() do
      ^benchmark -> :ok
      other -> raise("the hasher answered #{inspect(other)}, expected #{inspect(benchmark)}")
    end

    put_operator(context, %{benchmark_report: report, report: report})
  end

  # The storage tasks refuse unknown options with their usage line (BN-CLI-24).
  # The unit layer proves the refusal stops at the option check: `parse!/1`
  # raises before the application boots, so no root is ever touched and there
  # is no tree to snapshot. The integration adapter snapshots a real root.
  def seed_isolated_root(context) do
    put_operator(context, %{isolated_root: :isolated, parsed?: false})
  end

  def run_storage_task(context, task, arguments) do
    module =
      case task do
        "bnest.storage.migrate" -> MigrateTask
        "bnest.storage.relocate" -> RelocateTask
        "bnest.storage.retire" -> RetireTask
        "purge_test_data" -> PurgeTask
        "bnest.schema.audit" -> AuditTask
      end

    argv = String.split(arguments, " ", trim: true)

    refusal =
      try do
        _options = module.parse!(argv)
        :parsed
      rescue
        error in Mix.Error -> Exception.message(error)
      end

    put_operator(context, %{refusal: refusal, parsed?: refusal == :parsed})
  end

  def assert_refusal(context, expected) do
    %{refusal: refusal, parsed?: parsed?} = context.operator

    unless refusal == expected,
      do: raise("the task refused with #{inspect(refusal)}, expected #{inspect(expected)}")

    if parsed?,
      do: raise("the options parsed when the scenario expects a refusal")

    context
  end

  # node tools/test-data-cleanup.mjs (BN-CLI-25, BN-CLI-26).

  # The unit layer proves the reviewed setup-to-counts contract through the
  # model: the real sweep over temporary trees is proven by the Node suite and
  # by the integration adapter below, since the Elixir unit layer may not run
  # the script as a process.
  def seed_test_home(context, setup) do
    {removed, retained} = Model.cleanup_expectation(setup)

    put_operator(context, %{setup: setup, expected: {removed, retained}})
  end

  def run_cleanup(context) do
    {removed, retained} = context.operator.expected
    line = "test data cleanup: removed=#{removed} retained=#{retained}"
    put_operator(context, %{cleanup_line: line})
  end

  def assert_cleanup_line(context, expected) do
    line = context.operator.cleanup_line

    unless line == expected,
      do: raise("the cleanup printed #{inspect(line)}, expected #{inspect(expected)}")

    context
  end

  def run_cleanup_with(context, arguments) do
    argv = String.split(arguments, " ", trim: true)

    refusal =
      case Model.parse_cleanup_args(argv) do
        {:ok, _hours} -> raise "the arguments were expected to be refused: #{inspect(argv)}"
        {:error, message} -> message
      end

    put_operator(context, %{cleanup_refusal: refusal})
  end

  def assert_cleanup_refusal(context, expected) do
    refusal = context.operator.cleanup_refusal

    unless refusal == expected,
      do: raise("the cleanup refused with #{inspect(refusal)}, expected #{inspect(expected)}")

    context
  end

  # Runs a print through the process shell and returns what it printed, so
  # the unit layer observes the exact info line without a booted application.
  defp capture_print(fun) do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    try do
      fun.()
      flush_info([])
    after
      Mix.shell(previous)
    end
  end

  defp flush_info(lines) do
    receive do
      {:mix_shell, :info, [line]} -> flush_info([line | lines])
    after
      0 -> Enum.reverse(lines)
    end
  end
end
