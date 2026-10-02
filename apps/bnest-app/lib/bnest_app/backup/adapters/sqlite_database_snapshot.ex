defmodule BnestApp.Backup.Adapters.SqliteDatabaseSnapshot do
  @moduledoc """
  `BnestApp.Backup.Ports.DatabaseSnapshot` over the authoritative SQLite database: the
  dedicated (non-pooled) connection `VACUUM INTO` with cooperative timeout and cancellation
  through `Exqlite.Sqlite3.cancel/1`, the independent integrity and logical proof, and the
  restore into an isolated, ownership-marked root.
  """

  @behaviour BnestApp.Backup.Ports.DatabaseSnapshot

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage

  @progress_handler_steps 2_000
  @cancel_grace_ms 5_000

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def source_path(_snapshot), do: Storage.database_path()

  @impl true
  def source_generation(_snapshot), do: Storage.database_generation()

  # A dedicated, non-pooled connection: a `VACUUM INTO` that ran on a
  # borrowed `SqliteRepo` pool connection (the pre-Phase-5 shape) held that
  # connection, and the forced `PRAGMA wal_checkpoint(FULL)` that used to
  # precede it, out of ordinary application traffic for the whole backup
  # duration. Opening our own connection here, plus `set_busy_timeout/2` and
  # `set_progress_handler_steps/2` (both required for `cancel/1` to reach a
  # busy-wait or long-running statement -- see their own docs), is what
  # makes the deadline below a genuine abort rather than an unbounded wait.
  @impl true
  def vacuum_into(_snapshot, partial_path, timeout_ms) do
    source = SqliteRepo.main_database_path()
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

  @impl true
  def prove(_snapshot, path) do
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

  # The root is created before anything that may fail, and removed whatever happens; any
  # failure after it exists is reported as a failed restore.
  @impl true
  def restore(_snapshot, artifact_path) do
    root = isolated_restore_root!()
    restored_path = Path.join(root, "restored.sqlite3")

    try do
      File.cp!(artifact_path, restored_path)
      {:ok, connection} = Exqlite.Sqlite3.open(restored_path, mode: :readonly)

      try do
        {:ok, restored_facts(connection)}
      after
        :ok = Exqlite.Sqlite3.close(connection)
      end
    rescue
      _error -> {:error, :restore_failed}
    after
      File.rm_rf(root)
    end
  end

  @impl true
  def message_exists?(_snapshot, room_id, message_id) do
    %{rows: rows} =
      SqliteRepo.query!(
        "SELECT 1 FROM family_chat_messages WHERE id = ? AND room_id = ?",
        [message_id, room_id]
      )

    rows != []
  end

  defp escape_sql_literal(value), do: String.replace(value, "'", "''")

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

  defp restored_facts(connection) do
    # Scoped to ACTIVE rooms. The schema has carried `deleted_at` on
    # `family_chat_rooms` since the family chat migration, so an archived room
    # is a representable state -- and an unscoped single-row match turned that
    # representable state into a restore failure. Evidence is about the room
    # the product serves, which is the one that is not soft-deleted. The
    # single-row match stays: exactly one ACTIVE room is the v1 invariant, and
    # a restore that found two should still fail loudly.
    [[room_id, room_slug, room_name, member_posting_enabled]] =
      query_rows(
        connection,
        "SELECT id, slug, name, member_posting_enabled FROM family_chat_rooms WHERE deleted_at IS NULL ORDER BY id"
      )

    # Scoped to that same active room, for the same reason: these ids are read
    # back against the live room's messages, so an archived room's messages
    # would look like ids the restore invented. `room_id` is the INTEGER
    # primary key just read out of this same connection, never caller input,
    # so interpolating it into SQL carries no injection surface (`query_rows/2`
    # takes no bindings).
    message_ids =
      connection
      |> query_rows("SELECT id FROM family_chat_messages WHERE room_id = #{room_id} ORDER BY id")
      |> Enum.map(&hd/1)

    subscription_count =
      connection |> query_rows("SELECT COUNT(*) FROM web_push_subscriptions") |> hd() |> hd()

    delivery_states =
      connection
      |> query_rows("SELECT DISTINCT state FROM family_chat_push_deliveries ORDER BY state")
      |> Enum.map(&hd/1)

    %{
      room: %{
        id: room_id,
        slug: room_slug,
        name: room_name,
        member_posting_enabled: member_posting_enabled == 1
      },
      message_ids: message_ids,
      subscription_count: subscription_count,
      delivery_states: delivery_states
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
