defmodule BnestApp.Backup do
  @moduledoc """
  The public backup/restore service (Phase 5). Owns every SQL-touching step
  of one backup run -- measured capacity, the dedicated (non-pooled)
  connection `VACUUM INTO`, cooperative timeout/cancellation via
  `Exqlite.Sqlite3.cancel/1`, independent integrity/logical proof, and
  restore-into-an-isolated-marked-root -- so `BnestApp.Backup.Run` (the
  Scheduler-registered handler) can delegate to it without any direct SQL of
  its own (`family_chat_operations.feature`'s "the handler delegates to the
  public 'BnestApp.Backup' service without direct SQL").

  This module knows nothing about Scheduler claims/leases; `Backup.Run`
  translates between a Scheduler claim and this module's plain `run/1`
  options, and is the only caller that persists a claim-shaped receipt.
  """

  alias BnestApp.Backup.Capacity
  alias BnestApp.Backup.Config
  alias BnestApp.FamilyChat

  @progress_handler_steps 2_000
  @cancel_grace_ms 5_000
  @default_timeout_ms 1_800_000
  @probe_count 20

  @type artifact :: %{
          path: String.t(),
          basename: String.t(),
          sha256: String.t(),
          bytes: non_neg_integer(),
          quick_check: String.t(),
          schema_versions: [integer()],
          logical_proof_sha256: String.t(),
          source_generation: String.t() | nil
        }

  @doc """
  Runs one full backup against the configured (or, for tests only,
  explicitly injected -- see `opts[:destination_directory]`) destination.

  Options:
    * `:deadline` -- the `DateTime` to treat as "now" for the artifact's
      timestamp-derived basename and receipt facts. Defaults to
      `DateTime.utc_now/0`; production callers never need to pass this.
    * `:destination_directory` -- test-only dependency injection seam
      (production always resolves the destination through
      `BnestApp.Backup.Config.resolve/0`, exactly like every other caller).
    * `:capacity_check` -- test-only seam: `:insufficient` forces the
      retryable insufficient-capacity outcome without touching disk state,
      for exercising that failure path deterministically.
    * `:probe_watch` -- when truthy, runs a bounded authenticated Family
      Chat read/send workload concurrently with the backup and reports
      `probe_failures`, `probe_p95_ms`, and `probe_sent_ids_missing` in the
      success result.
  """
  @spec run(keyword()) ::
          {:ok, map()} | {:error, {:retryable, atom(), artifact() | nil}} | {:error, atom()}
  def run(opts \\ []) do
    now = Keyword.get(opts, :deadline, DateTime.utc_now())
    started_at = System.monotonic_time(:millisecond)
    :telemetry.execute([:bnest_app, :backup, :start], %{system_time: System.system_time()}, %{})

    result =
      with {:ok, directory} <- resolve_directory(opts),
           :ok <- check_capacity(directory, opts[:capacity_check]) do
        create_backup(directory, now, opts)
      end

    :telemetry.execute(
      [:bnest_app, :backup, :stop],
      %{duration_ms: System.monotonic_time(:millisecond) - started_at},
      %{outcome: outcome_tag(result)}
    )

    result
  end

  @doc """
  Restores an artifact (as returned in `run/1`'s success map) into a fresh,
  function-owned, ownership-marked temporary root -- never the caller's
  choice of path, so restore can never target (or be mistaken for) a live
  database. Returns redacted `evidence` (structural counts/ids/states only,
  never a message body or push credential) proving the room, ordered
  messages, subscription structure, and delivery states are all readable
  back out of the restored copy.
  """
  @spec restore(map()) :: {:ok, map()} | {:error, atom()}
  def restore(%{path: artifact_path}) when is_binary(artifact_path) do
    root = isolated_restore_root!()
    restored_path = Path.join(root, "restored.sqlite3")

    try do
      File.cp!(artifact_path, restored_path)
      {:ok, connection} = Exqlite.Sqlite3.open(restored_path, mode: :readonly)

      try do
        {:ok, %{evidence: Jason.encode!(restore_evidence(connection))}}
      after
        :ok = Exqlite.Sqlite3.close(connection)
      end
    rescue
      _error -> {:error, :restore_failed}
    after
      File.rm_rf(root)
    end
  end

  def restore(_invalid_artifact), do: {:error, :invalid_artifact}

  # `:destination_directory`, when given, is already a validated/created
  # directory (either `Run.execute/2`'s own `Config.resolve/0` result, or a
  # test-only isolated fixture directory) -- resolving it again here would
  # be redundant, and for the test-fixture case would also fail
  # `Location.validate/1` (it deliberately validates a narrower set of
  # directories than tests need to construct in isolation).
  defp resolve_directory(opts) do
    case Keyword.get(opts, :destination_directory) do
      nil ->
        case Config.resolve() do
          {:ok, location} -> {:ok, location.directory}
          {:error, reason} -> {:error, reason}
        end

      directory ->
        {:ok, directory}
    end
  end

  defp check_capacity(_directory, :insufficient),
    do: {:error, {:retryable, :insufficient_capacity, nil}}

  defp check_capacity(directory, _real_check) do
    if Capacity.sufficient?(directory),
      do: :ok,
      else: {:error, {:retryable, :insufficient_capacity, nil}}
  end

  defp create_backup(directory, now, opts) do
    timestamp = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    run_id = Base.url_encode64(:crypto.strong_rand_bytes(15), padding: false)
    artifact_basename = "bnest-prod-#{timestamp}-#{run_id}.sqlite3"
    artifact_path = Path.join(directory, artifact_basename)
    partial_path = artifact_path <> ".partial"
    File.rm(partial_path)

    source = BnestApp.SqliteRepo.main_database_path()
    probe_task = maybe_start_probes(opts[:probe_watch])
    before_promote = Keyword.get(opts, :before_promote, fn -> :ok end)

    case vacuum_into(source, partial_path, timeout_ms()) do
      :ok ->
        finalize_artifact(
          partial_path,
          artifact_path,
          artifact_basename,
          probe_task,
          before_promote
        )

      {:error, category} ->
        File.rm(partial_path)
        await_probes(probe_task)
        {:error, {:retryable, category, nil}}
    end
  end

  # A dedicated, non-pooled connection: a `VACUUM INTO` that ran on a
  # borrowed `SqliteRepo` pool connection (the pre-Phase-5 shape) held that
  # connection, and the forced `PRAGMA wal_checkpoint(FULL)` that used to
  # precede it, out of ordinary application traffic for the whole backup
  # duration. Opening our own connection here, plus `set_busy_timeout/2` and
  # `set_progress_handler_steps/2` (both required for `cancel/1` to reach a
  # busy-wait or long-running statement -- see their own docs), is what
  # makes the deadline below a genuine abort rather than an unbounded wait.
  defp vacuum_into(source, partial_path, timeout_ms) do
    {:ok, connection} = Exqlite.Sqlite3.open(source, mode: :readonly)
    :ok = Exqlite.Sqlite3.set_busy_timeout(connection, timeout_ms)
    :ok = Exqlite.Sqlite3.set_progress_handler_steps(connection, @progress_handler_steps)

    sql = "VACUUM INTO '" <> escape_sql_literal(partial_path) <> "'"
    task = Task.async(fn -> Exqlite.Sqlite3.execute(connection, sql) end)

    outcome =
      case Task.yield(task, timeout_ms) do
        {:ok, :ok} ->
          :ok

        # `io_failed`: tech-doc 009's Observability section names the
        # closed, safe retryable-category vocabulary ("insufficient_capacity,
        # busy, timeout, cancelled, integrity_failed, stale_claim, or
        # io_failed") explicitly so telemetry and Scheduler retry state never
        # carry a raw exception/path string; a live `VACUUM INTO` execute
        # error or an unexpected task exit are both bucketed here rather than
        # surfacing `_reason` (which could itself contain a path).
        {:ok, {:error, _reason}} ->
          {:error, :io_failed}

        {:exit, _reason} ->
          {:error, :io_failed}

        nil ->
          :ok = Exqlite.Sqlite3.cancel(connection)
          _ = Task.yield(task, @cancel_grace_ms) || Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end

    :ok = Exqlite.Sqlite3.close(connection)
    outcome
  end

  defp escape_sql_literal(value), do: String.replace(value, "'", "''")

  defp finalize_artifact(
         partial_path,
         artifact_path,
         artifact_basename,
         probe_task,
         before_promote
       ) do
    File.chmod!(partial_path, 0o600)

    case independent_proof(partial_path) do
      {:ok, proof} ->
        sync_file!(partial_path)
        promote(partial_path, artifact_path, artifact_basename, proof, probe_task, before_promote)

      {:error, :corrupt} ->
        File.rm(partial_path)
        await_probes(probe_task)
        # `integrity_failed`: tech-doc 009's documented category name for
        # this case (see `vacuum_into/3`'s identical `io_failed` comment for
        # the whole vocabulary this module draws from).
        {:error, {:retryable, :integrity_failed, nil}}
    end
  end

  # `before_promote` runs as late as possible -- right before the rename
  # that makes this artifact the canonical, retained one -- to keep the
  # race window between "are we still the owner of this run" and "commit
  # the result" as small as possible. `BnestApp.Backup.Run` (the Scheduler
  # handler) uses this to re-check its claim's lease without this module
  # ever needing to know what a Scheduler claim is.
  defp promote(partial_path, artifact_path, artifact_basename, proof, probe_task, before_promote) do
    case before_promote.() do
      :ok ->
        File.rename!(partial_path, artifact_path)

        artifact = %{
          path: artifact_path,
          basename: artifact_basename,
          sha256: sha256_file(artifact_path),
          bytes: File.stat!(artifact_path).size,
          quick_check: "ok",
          schema_versions: proof.schema_versions,
          logical_proof_sha256: proof.logical_sha256,
          source_generation: BnestApp.Storage.Config.database_generation()
        }

        merge_probe_result({:ok, artifact}, probe_task)

      {:error, reason} ->
        File.rm(partial_path)
        await_probes(probe_task)
        {:error, {:retryable, reason, nil}}
    end
  end

  defp independent_proof(path) do
    {:ok, connection} = Exqlite.Sqlite3.open(path, mode: :readonly)

    try do
      case query_rows(connection, "PRAGMA quick_check") do
        [["ok"]] ->
          schema_versions =
            connection
            |> query_rows("SELECT version FROM schema_migrations ORDER BY version")
            |> Enum.map(&hd/1)

          logical_rows =
            query_rows(
              connection,
              "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
            )

          logical_sha256 =
            %{schema_versions: schema_versions, schema: logical_rows}
            |> Jason.encode!()
            |> then(&:crypto.hash(:sha256, &1))
            |> Base.encode16(case: :lower)

          {:ok, %{schema_versions: schema_versions, logical_sha256: logical_sha256}}

        _not_ok ->
          {:error, :corrupt}
      end
    after
      :ok = Exqlite.Sqlite3.close(connection)
    end
  end

  defp query_rows(connection, sql) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(connection, sql)

    try do
      collect_rows(connection, statement, [])
    after
      :ok = Exqlite.Sqlite3.release(connection, statement)
    end
  end

  defp collect_rows(connection, statement, rows) do
    case Exqlite.Sqlite3.step(connection, statement) do
      {:row, row} -> collect_rows(connection, statement, [row | rows])
      :done -> Enum.reverse(rows)
      {:error, reason} -> raise "backup proof query failed: #{inspect(reason)}"
    end
  end

  defp sync_file!(path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :binary])
    :ok = :file.sync(file)
    :ok = :file.close(file)
  end

  defp sha256_file(path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :binary, :raw])

    try do
      file
      |> hash_chunks(:crypto.hash_init(:sha256))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    after
      :ok = :file.close(file)
    end
  end

  defp hash_chunks(file, hash) do
    case :file.read(file, 64 * 1024) do
      {:ok, bytes} -> hash_chunks(file, :crypto.hash_update(hash, bytes))
      :eof -> hash
      {:error, reason} -> raise "backup digest failed: #{inspect(reason)}"
    end
  end

  defp timeout_ms, do: Application.get_env(:bnest_app, :backup_timeout_ms, @default_timeout_ms)

  defp outcome_tag({:ok, _artifact}), do: :ok
  defp outcome_tag({:error, {:retryable, category, _artifact}}), do: category
  defp outcome_tag({:error, category}), do: category

  # --- concurrent-write load proof (unit-layer mechanism proxy) ---
  #
  # Continuous authenticated Family Chat read/send probes, run on the same
  # live `SqliteRepo` pool the backup's dedicated connection reads from
  # concurrently -- this is the real mechanism a routed HTTP probe would
  # eventually reach (`BnestApp.FamilyChat.send_message/4` and
  # `list_messages/3`, the exact functions the GraphQL resolvers call), just
  # below the HTTP/socket boundary the unit test layer cannot cross (see
  # `test/behaviour/verify.exs`'s `BoundaryPolicy`). The routed, full-stack
  # version of this proof lives at the integration layer (learnings.md's
  # Phase 5 entry).
  defp maybe_start_probes(truthy) when truthy in [nil, false], do: nil

  defp maybe_start_probes(_truthy) do
    Task.async(fn -> run_probes() end)
  end

  defp run_probes do
    slug = FamilyChat.canonical_room_slug()

    user_id =
      "test-user-backup-probe-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    {sent_ids, samples, failures} =
      Enum.reduce(1..@probe_count, {[], [], 0}, fn index, {sent_ids, samples, failures} ->
        # `FamilyChat.send_message/4` requires a UUID-shaped client message
        # id (`FamilyChat.Message.valid_client_message_id?/1`) -- anything
        # else is a `VALIDATION_FAILED` error, not a transient probe failure.
        client_message_id = Ecto.UUID.generate()

        {send_ms, send_result} =
          timed(fn ->
            FamilyChat.send_message(user_id, slug, client_message_id, "probe #{index}")
          end)

        {read_ms, read_result} =
          timed(fn -> FamilyChat.list_messages(user_id, slug, limit: 1) end)

        ok? = match?({:ok, %{}}, send_result) and match?({:ok, %{}}, read_result)

        sent_ids =
          if match?({:ok, %{id: _}}, send_result),
            do: [elem(send_result, 1).id | sent_ids],
            else: sent_ids

        {sent_ids, [send_ms, read_ms | samples], failures + if(ok?, do: 0, else: 1)}
      end)

    %{sent_ids: sent_ids, samples: samples, failures: failures}
  end

  defp timed(fun) do
    started = System.monotonic_time(:millisecond)

    try do
      {System.monotonic_time(:millisecond) - started, fun.()}
    rescue
      error -> {System.monotonic_time(:millisecond) - started, {:error, error}}
    end
  end

  defp merge_probe_result(ok_result, nil), do: ok_result

  defp merge_probe_result({:ok, artifact}, probe_task) do
    probes = await_probes(probe_task)
    missing = missing_sent_ids(probes.sent_ids)

    {:ok,
     Map.merge(artifact, %{
       probe_failures: probes.failures,
       probe_p95_ms: percentile(probes.samples, 95),
       probe_sent_ids_missing: missing
     })}
  end

  defp await_probes(nil), do: %{sent_ids: [], samples: [0], failures: 0}
  defp await_probes(task), do: Task.await(task, 60_000)

  defp missing_sent_ids(sent_ids), do: Enum.reject(sent_ids, &message_exists?/1)

  defp message_exists?(message_id) do
    room = FamilyChat.Store.get_active_room_by_slug(FamilyChat.canonical_room_slug())

    %{rows: rows} =
      BnestApp.SqliteRepo.query!(
        "SELECT 1 FROM family_chat_messages WHERE id = ? AND room_id = ?",
        [message_id, room.id]
      )

    rows != []
  end

  defp percentile([], _p), do: 0

  defp percentile(samples, p) do
    sorted = Enum.sort(samples)
    count = length(sorted)
    index = max(0, ceil(p / 100 * count) - 1)
    Enum.at(sorted, index)
  end

  defp restore_evidence(connection) do
    [[room_id, room_slug, room_name, member_posting_enabled]] =
      query_rows(
        connection,
        "SELECT id, slug, name, member_posting_enabled FROM family_chat_rooms ORDER BY id"
      )

    message_ids =
      connection
      |> query_rows("SELECT id FROM family_chat_messages ORDER BY id")
      |> Enum.map(&hd/1)

    subscription_count =
      connection |> query_rows("SELECT COUNT(*) FROM web_push_subscriptions") |> hd() |> hd()

    delivery_states =
      connection
      |> query_rows("SELECT DISTINCT state FROM family_chat_push_deliveries ORDER BY state")
      |> Enum.map(&hd/1)

    %{
      "room" => %{
        "id" => room_id,
        "slug" => room_slug,
        "name" => room_name,
        "memberPostingEnabled" => member_posting_enabled == 1
      },
      "orderedMessageIds" => message_ids,
      "subscriptionCount" => subscription_count,
      "deliveryStates" => delivery_states
    }
  end

  defp isolated_restore_root! do
    root =
      Path.join(
        System.tmp_dir!(),
        "bnest-restore-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir_p!(root)
    File.chmod!(root, 0o700)

    File.write!(
      Path.join(root, ".bnest-restore-root.json"),
      Jason.encode!(%{"schemaVersion" => 1, "ownershipScope" => "bnest-production-restores-v1"})
    )

    root
  end
end
