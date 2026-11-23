defmodule BnestApp.Behaviour.OperatorCommands.NotArgon2idHasher do
  @moduledoc false
  @behaviour BnestApp.Identity.Ports.CredentialHasher

  @impl true
  def hash(_password), do: {:ok, "not-argon2id"}

  @impl true
  def verify(_password, _verifier), do: false

  @impl true
  def no_user_verify, do: false

  @impl true
  def benchmark, do: {:error, :not_argon2id}
end

defmodule BnestApp.Behaviour.OperatorCommands.IntegrationAdapter do
  @moduledoc """
  The integration layer's adapter for `operator_commands.feature`. Where the
  review binds a scenario at integration, it runs the real implementation
  against an isolated run base: the Storage and Identity facades over real
  SQLite, the task `run/1` entry points with bad options, and the Node
  cleanup script as a child process. Where the review exempts integration,
  it delegates to the same pure model the unit adapter drives, since no
  integration boundary observes the exempt behaviour.
  """

  alias BnestApp.Behaviour.OperatorCommands.NotArgon2idHasher
  alias BnestApp.Behaviour.OperatorCommands.UnitAdapter, as: Unit
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Storage.Migration, as: StorageMigration
  alias BnestApp.TestRuntimeRoot
  alias Mix.Tasks.Bnest.Identity.Benchmark, as: BenchmarkTask
  alias Mix.Tasks.Bnest.Schema.Audit, as: AuditTask
  alias Mix.Tasks.Bnest.Storage.Migrate, as: MigrateTask
  alias Mix.Tasks.Bnest.Storage.PurgeTestData, as: PurgeTask
  alias Mix.Tasks.Bnest.Storage.Relocate, as: RelocateTask
  alias Mix.Tasks.Bnest.Storage.Retire, as: RetireTask

  @generation "gen"
  @now_ms DateTime.to_unix(~U[2026-08-29 12:00:00Z], :millisecond)

  @doc "Installs the operator state in the scenario context."
  def install(context) do
    context
    |> Map.put(:operator_adapter, __MODULE__)
    |> Map.put(:operator, %{})
  end

  @doc "Nothing to release: the scenario context is discarded with the test."
  def release(context), do: context

  defp put_operator(context, patch),
    do: %{context | operator: Map.merge(context.operator, patch)}

  # mix bnest.storage.purge_test_data (BN-CLI-21): bound, so the purge runs
  # against real SQLite in an isolated run base.

  def seed_generation(context) do
    runtime = TestRuntimeRoot.create!("operator-purge")
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    previous_pointer = System.get_env("BNEST_STORAGE_CONFIG")
    System.put_env("BNEST_STORAGE_CONFIG", Path.join(runtime.path, "pointer/storage.json"))
    {:ok, _config} = Storage.persist_directory(runtime.sqlite_path)
    :ok = SqliteCoordinator.ensure_started!(database_path)
    {:ok, _versions, _apps} = migrate(:up)
    _run = StorageMigration.run(runtime.path)
    :ok = StorageMigration.activate!()

    FileConfigStore.restore!(
      FileConfigStore.read()
      |> elem(1)
      |> Map.put("databaseGeneration", @generation)
    )

    insert_fixture_records!()

    on_exit(fn ->
      SqliteCoordinator.stop()

      if previous_pointer == nil,
        do: System.delete_env("BNEST_STORAGE_CONFIG"),
        else: System.put_env("BNEST_STORAGE_CONFIG", previous_pointer)

      TestRuntimeRoot.cleanup!(runtime)
    end)

    put_operator(context, %{
      generation: @generation,
      runtime: runtime,
      counts_before: record_counts()
    })
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

    put_operator(context, %{purge_report: purge_report, counts_after: record_counts()})
  end

  defp purge(_context, %{generation: generation, dry_run?: dry_run?}) do
    case Storage.purge_test_data(generation, dry_run?) do
      {:ok, counts} ->
        {:printed, PurgeTask.report_line(dry_run?, {:ok, counts}), dry_run?}

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
    case context.operator do
      # The benchmark timing is real at integration, so only its class is
      # scenario data: the cost and the secret-free shape are asserted here.
      # The refusal row reports the reviewed fixed sentence instead of a line.
      %{benchmark_report: "configured password hasher did not produce Argon2id" = line} ->
        unless expected == line,
          do: raise("the task reported #{inspect(line)}, expected #{inspect(expected)}")

      %{benchmark_report: line} ->
        cost = context.operator.cost

        unless line ==
                 "argon2id memory_kib=#{cost[:memory_kib]} iterations=#{cost[:time_cost]} " <>
                   "parallelism=#{cost[:parallelism]} timing_class=#{benchmark_timing(line)}" do
          raise "the benchmark reported #{inspect(line)}, expected the reviewed cost with a timing class"
        end

        unless String.starts_with?(expected, "argon2id memory_kib="),
          do: raise("the scenario expects #{inspect(expected)}, not a benchmark line")

        if line =~ ~r/\$argon2id|\$2[aby]\$|[0-9a-f]{32,}/i,
          do: raise("the benchmark line carries a secret: #{inspect(line)}")

      %{purge_report: {_kind, line, _dry?}} ->
        unless line == expected,
          do: raise("the task reported #{inspect(line)}, expected #{inspect(expected)}")

      %{audit_line: line} ->
        unless line == expected,
          do: raise("the task reported #{inspect(line)}, expected #{inspect(expected)}")
    end

    context
  end

  defp benchmark_timing(line) do
    ["under-one-second", "one-second-or-more"]
    |> Enum.find(fn class -> String.ends_with?(line, "timing_class=#{class}") end)
    |> case do
      nil -> raise "the benchmark line names no timing class: #{inspect(line)}"
      class -> class
    end
  end

  def assert_legacy_state(context, "kept") do
    %{counts_before: before, counts_after: after_counts} = context.operator

    case context.operator.purge_report do
      {:printed, _line, true} ->
        unless after_counts == before,
          do: raise("a dry run changed the database: #{inspect(after_counts)}")

      {:raised, _message, _dry?} ->
        unless after_counts == before,
          do: raise("a refused purge changed the database: #{inspect(after_counts)}")
    end

    context
  end

  def assert_legacy_state(context, "removed") do
    %{counts_after: {records, sources}} = context.operator

    unless records == ["user-family"] and sources == ["user-family"] do
      raise(
        "the purge kept #{inspect(records)} and #{inspect(sources)}, expected only the family data"
      )
    end

    context
  end

  # mix bnest.schema.audit (BN-CLI-22): bound, so the audit reads an
  # isolated root from disk.

  def seed_audit_roots(context) do
    default_runtime = TestRuntimeRoot.create!("operator-audit-default")
    other_runtime = TestRuntimeRoot.create!("operator-audit-other")
    default_root = default_runtime.path
    other_root = other_runtime.path
    previous_runtime_root = Application.get_env(:bnest_app, :runtime_root)
    Application.put_env(:bnest_app, :runtime_root, default_root)

    ExUnit.Callbacks.on_exit(fn ->
      if previous_runtime_root == nil,
        do: Application.delete_env(:bnest_app, :runtime_root),
        else: Application.put_env(:bnest_app, :runtime_root, previous_runtime_root)

      TestRuntimeRoot.cleanup!(default_runtime)
      TestRuntimeRoot.cleanup!(other_runtime)
    end)

    File.write!(
      Path.join(default_root, "chat-user-audit.json"),
      Jason.encode!(%{
        "schemaVersion" => 1,
        "recordType" => "chat",
        "ownerId" => "user-audit",
        "sourceImportId" => nil,
        "revision" => 0,
        "state" => %{
          "version" => 2,
          "thread_id" => nil,
          "model" => "fixture-model",
          "reasoning_effort" => "medium",
          "messages" => []
        },
        "updatedAt" => "2030-01-01T00:00:00Z"
      })
    )

    File.write!(
      Path.join(other_root, "chat-user-audit.json"),
      Jason.encode!(%{"schemaVersion" => 1, "recordType" => "chat"})
    )

    put_operator(context, %{audit_roots: %{default: default_root, other: other_root}})
  end

  def run_audit(context, arguments) do
    root =
      case arguments do
        "(default root)" -> Application.fetch_env!(:bnest_app, :runtime_root)
        "(other root)" -> context.operator.audit_roots.other
        "(refused root)" -> System.tmp_dir!()
      end

    outcome =
      case Storage.audit_schema(root) do
        {:ok, results} ->
          lines = Enum.map(results, &AuditTask.format_result/1)

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

    line =
      case outcome do
        {:ok, audit_line, _check} -> audit_line
        {:error, {:raised, message}} -> message
      end

    put_operator(context, %{audit_outcome: outcome, audit_line: line})
  end

  defdelegate assert_audit_outcome(context, expected), to: Unit

  # mix bnest.identity.benchmark (BN-CLI-23): bound, so the real Argon2
  # hasher times a real hash with the test cost.

  # The real Argon2id hasher always produces Argon2id, so the refusal row
  # swaps the credential hasher for a double that answers a non-Argon2id
  # hash: the task then takes the same refusal path it takes in production.
  def seed_timing(context, "not Argon2id") do
    cost = Application.fetch_env!(:bnest_app, :argon2)
    previous = Application.fetch_env!(:bnest_app, BnestApp.Identity)
    refusing = Keyword.put(previous, :credential_hasher, NotArgon2idHasher)
    Application.put_env(:bnest_app, BnestApp.Identity, refusing)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, BnestApp.Identity, previous)
    end)

    put_operator(context, %{cost: cost, refusing?: true})
  end

  def seed_timing(context, _timing) do
    cost = Application.fetch_env!(:bnest_app, :argon2)
    put_operator(context, %{cost: cost, refusing?: false})
  end

  def run_benchmark(context) do
    cost = context.operator.cost

    {elapsed_ms, line} =
      case BnestApp.Identity.benchmark_hasher() do
        {:ok, elapsed_ms} ->
          if context.operator.refusing?,
            do: raise("the refusing hasher produced a hash")

          {elapsed_ms, BenchmarkTask.report_line(cost, elapsed_ms)}

        {:error, :not_argon2id} ->
          unless context.operator.refusing?,
            do: raise("the test hasher did not produce Argon2id")

          {nil, "configured password hasher did not produce Argon2id"}
      end

    # Only a measured line carries values to check: the refusal is the
    # reviewed fixed sentence, which names the hasher but no secret.
    if is_integer(elapsed_ms) do
      unless elapsed_ms >= 0,
        do: raise("the benchmark timed #{inspect(elapsed_ms)}")

      if line =~ ~r/\$argon2id|\$2[aby]\$|[0-9a-f]{32,}/i,
        do: raise("the benchmark line carries a secret: #{inspect(line)}")
    end

    put_operator(context, %{benchmark_report: line, report: line})
  end

  # The storage tasks refuse unknown options with their usage line (BN-CLI-24):
  # bound, so each task's `run/1` runs with bad options against an isolated
  # root. The option check raises before the application boots, so the root
  # stays untouched.

  def seed_isolated_root(context) do
    root = Path.join(System.tmp_dir!(), "bnest-operator-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(root)

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)

    put_operator(context, %{isolated_root: root, root_before: tree_state(root)})
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
        module.run(argv)
        :parsed
      rescue
        error in Mix.Error -> Exception.message(error)
      end

    put_operator(context, %{
      refusal: refusal,
      root_after: tree_state(context.operator.isolated_root)
    })
  end

  def assert_refusal(context, expected) do
    %{refusal: refusal, root_before: before, root_after: after_root} = context.operator

    unless refusal == expected,
      do: raise("the task refused with #{inspect(refusal)}, expected #{inspect(expected)}")

    unless after_root == before,
      do: raise("the refused task changed the isolated root")

    context
  end

  # node tools/test-data-cleanup.mjs (BN-CLI-25): bound, so the real script
  # runs as a child process against temporary roots. The script's own
  # defaults point at the real run trees, so the child drives it through an
  # inline module that passes temporary roots explicitly, exactly as the
  # script's `main` passes its own.

  def seed_test_home(context, setup) do
    home =
      Path.join(System.tmp_dir!(), "bnest-cleanup-home-#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(home)

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(home) end)

    roots = build_test_home(home, setup)

    put_operator(context, %{test_home: home, setup: setup, roots: roots})
  end

  def run_cleanup(context) do
    %{roots: roots, setup: setup} = context.operator

    {output, status} =
      System.cmd("node", ["--input-type=module", "--eval", cleanup_eval(roots)],
        stderr_to_stdout: true
      )

    line = String.trim(output)
    expected = "test data cleanup: removed=#{roots.removed} retained=#{roots.retained}"

    unless status == 0,
      do: raise("the cleanup child exited #{status} for #{setup}: #{inspect(output)}")

    unless line == expected,
      do:
        raise("the cleanup printed #{inspect(line)}, expected #{inspect(expected)} for #{setup}")

    put_operator(context, %{cleanup_line: line})
  end

  def assert_cleanup_line(context, expected) do
    line = context.operator.cleanup_line

    unless line == expected,
      do: raise("the cleanup printed #{inspect(line)}, expected #{inspect(expected)}")

    context
  end

  # Test-data cleanup refuses bad arguments and negative hours (BN-CLI-26):
  # bound, so the real script runs as a child process with bad arguments. The
  # refusal raises before the sweep, so the temporary tree stays unchanged.

  def run_cleanup_with(context, arguments) do
    home = context.operator.test_home
    before = tree_state(home)
    tool = Path.expand("../../../tools/test-data-cleanup.mjs", __DIR__)
    argv = String.split(arguments, " ", trim: true)

    {output, status} =
      System.cmd("node", [tool | argv],
        env: [{"HOME", home}],
        stderr_to_stdout: true
      )

    # An uncaught throw prints the file line, the `Error:` line and the
    # stack, so the assertion matches the refusal text anywhere in it.
    message = output

    put_operator(context, %{
      cleanup_refusal: message,
      cleanup_status: status,
      tree_before: before,
      tree_after: tree_state(home)
    })
  end

  def assert_cleanup_refusal(context, expected) do
    %{cleanup_refusal: refusal, cleanup_status: status} = context.operator

    unless String.contains?(refusal, expected),
      do: raise("the cleanup refused with #{inspect(refusal)}, expected #{inspect(expected)}")

    unless status != 0,
      do: raise("the refused cleanup exited #{status}, expected non-zero")

    unless context.operator.tree_after == context.operator.tree_before,
      do: raise("the refused cleanup changed the temporary tree")

    context
  end

  # --- isolated run base -----------------------------------------------------

  defp migrate(direction) do
    path = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

    Ecto.Migrator.with_repo(
      BnestApp.SqliteRepo,
      &Ecto.Migrator.run(&1, path, direction, all: true)
    )
  end

  defp insert_fixture_records! do
    insert_record!("account", "user-test-old", "user-test-old", %{
      "recordType" => "account",
      "userId" => "user-test-old"
    })

    insert_record!("username-index", "test-user-old", nil, %{
      "recordType" => "username-index",
      "normalizedUsername" => "test-user-old",
      "userId" => "user-test-old"
    })

    insert_record!("chat", "user-family", "user-family", %{
      "recordType" => "chat",
      "ownerId" => "user-family"
    })

    insert_recovery_source!("user", "user-test-old", "import-old")
    insert_recovery_source!("user", "user-family", "import-family")
  end

  defp insert_record!(record_type, record_key, owner_id, payload) do
    encoded = Jason.encode!(payload)
    sha = :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)

    BnestApp.SqliteRepo.query!(
      "INSERT INTO bnest_records (record_type, record_key, owner_id, schema_version, revision, payload_json, payload_sha256, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        record_type,
        record_key,
        owner_id,
        1,
        0,
        encoded,
        sha,
        "2030-01-01T00:00:00Z",
        "2030-01-01T00:00:00Z"
      ]
    )
  end

  defp insert_recovery_source!(owner_kind, owner_key, import_id) do
    BnestApp.SqliteRepo.query!(
      "INSERT INTO bnest_recovery_sources (owner_kind, owner_key, import_id, payload_blob, payload_sha256, byte_size, inserted_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      [
        owner_kind,
        owner_key,
        import_id,
        "bytes",
        Base.encode16(:crypto.hash(:sha256, "bytes"), case: :lower),
        5,
        "2030-01-01T00:00:00Z"
      ]
    )
  end

  defp record_counts do
    records =
      BnestApp.SqliteRepo.query!("SELECT record_key FROM bnest_records ORDER BY record_key").rows
      |> Enum.map(&hd/1)

    sources =
      BnestApp.SqliteRepo.query!(
        "SELECT owner_key FROM bnest_recovery_sources ORDER BY owner_key"
      ).rows
      |> Enum.map(&hd/1)

    {records, sources}
  end

  # --- temporary cleanup trees -----------------------------------------------

  defp build_test_home(home, "a stale marked run with a dead owner") do
    root = Path.join(home, "runs")

    run =
      marked_run(root, "old", "2026-01-01T00:00:00.000Z", %{
        "hostname" => "local",
        "pid" => 99_999_999
      })

    %{roots: [root], legacy_parents: [], removed: 1, retained: 0, entries: [run]}
  end

  defp build_test_home(home, "a young marked run") do
    root = Path.join(home, "runs")
    run = marked_run(root, "recent", "2026-08-29T11:30:00.000Z", %{})
    %{roots: [root], legacy_parents: [], removed: 0, retained: 1, entries: [run]}
  end

  defp build_test_home(home, "an unmarked directory") do
    root = Path.join(home, "runs")
    plain = Path.join(root, "unmarked")
    File.mkdir_p!(plain)
    %{roots: [root], legacy_parents: [], removed: 0, retained: 1, entries: [plain]}
  end

  defp build_test_home(home, "a stale marked run with a live owner") do
    root = Path.join(home, "runs")
    {:ok, hostname} = :inet.gethostname()
    pid = :os.getpid() |> to_string() |> String.to_integer()

    run =
      marked_run(root, "active", "2026-01-01T00:00:00.000Z", %{
        "hostname" => to_string(hostname),
        "pid" => pid
      })

    %{roots: [root], legacy_parents: [], removed: 0, retained: 1, entries: [run]}
  end

  defp build_test_home(home, "a stale legacy run") do
    parent = Path.join(home, "family-chat")
    File.mkdir_p!(parent)
    stale = Path.join(parent, "run-old")
    File.mkdir_p!(stale)
    File.touch!(stale, {{2026, 1, 1}, {0, 0, 0}})
    %{roots: [], legacy_parents: [parent], removed: 1, retained: 0, entries: [stale]}
  end

  defp build_test_home(home, "a symlinked run") do
    root = Path.join(home, "runs")
    outside = Path.join(home, "outside")
    File.mkdir_p!(outside)
    File.mkdir_p!(root)
    File.ln_s!(outside, Path.join(root, "linked"))
    %{roots: [root], legacy_parents: [], removed: 0, retained: 0, entries: []}
  end

  defp marked_run(root, run_id, created_at, extra) do
    directory = Path.join(root, run_id)
    File.mkdir_p!(directory)

    marker =
      Map.merge(
        %{
          "schemaVersion" => 1,
          "recordType" => "bnest-test-run",
          "runId" => run_id,
          "createdAt" => created_at,
          "owner" => "bnest-test-harness"
        },
        extra
      )

    File.write!(Path.join(directory, ".bnest-test-run.json"), Jason.encode!(marker))
    directory
  end

  # Drives the real cleanup module in a child process against temporary
  # roots, then prints the counts line in the script's exact `main` words.
  # The real `main` is not used because its default roots are the real run
  # trees, which a test must never sweep.
  defp cleanup_eval(%{roots: roots, legacy_parents: legacy_parents}) do
    tool = Path.expand("../../../tools/test-data-cleanup.mjs", __DIR__)

    """
    import {cleanupStaleTestData} from #{inspect("file://" <> tool)};
    const result = cleanupStaleTestData({
      roots: #{inspect(roots)},
      legacyParents: #{inspect(legacy_parents)},
      olderThanHours: 24,
      now: #{@now_ms}
    });
    process.stdout.write(`test data cleanup: removed=${result.removed} retained=${result.retained}\\n`);
    """
  end

  defp tree_state(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.sort()
  end

  defp on_exit(fun), do: ExUnit.Callbacks.on_exit(fun)
end
