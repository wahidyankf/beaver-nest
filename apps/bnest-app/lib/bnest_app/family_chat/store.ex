defmodule BnestApp.FamilyChat.Store do
  @moduledoc """
  Raw-SQL persistence for Family Chat, mirroring `BnestApp.Scheduler.Store`'s
  convention (no Ecto schema/changeset layer, direct `SqliteRepo.query!/2` calls,
  audit columns written explicitly). Every public function first self-heals the
  shared `SqliteRepo` connection onto Family Chat's database path: the SQLite
  connection is a single named process shared with other SQLite-backed features
  (scheduler, backup), and other tests/processes may stop or repoint it between
  calls, so each operation re-asserts its own connection rather than assuming a
  prior bootstrap is still in effect.
  """

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig

  @room_seed %{
    id: 1,
    slug: "ruang-keluarga",
    name: "Ruang Keluarga",
    room_kind: "conversation",
    member_posting_enabled: true
  }

  @retention_schedule_key "family-chat-push-retention-daily"

  @room_columns ~w(id slug name room_kind member_posting_enabled created_at created_by updated_at updated_by)a
  @message_columns ~w(id room_id sender_kind sender_id sender_display_name idempotency_key body committed_at reply_to_message_id)a

  @doc "The canonical v1 room slug, exposed so callers never hard-code it as authorization."
  @spec canonical_room_slug() :: String.t()
  def canonical_room_slug, do: @room_seed.slug

  @spec migrate!() :: {:ok, map()}
  def migrate! do
    ensure_ready!()
    {:ok, get_active_room_by_slug(@room_seed.slug)}
  end

  @spec list_active_rooms() :: [map()]
  def list_active_rooms do
    ensure_ready!()

    %{rows: rows} =
      SqliteRepo.query!(
        "SELECT #{columns(@room_columns)} FROM family_chat_rooms WHERE deleted_at IS NULL ORDER BY id"
      )

    Enum.map(rows, &room_row/1)
  end

  @spec get_active_room_by_slug(String.t()) :: map() | nil
  def get_active_room_by_slug(slug) when is_binary(slug) do
    ensure_ready!()
    fetch_active_room_by_slug(slug)
  end

  # Raw read, no `ensure_ready!()` — `seed_room!/0` (called FROM
  # `ensure_ready!/0`, to verify its own seed) must never call back through
  # the public `get_active_room_by_slug/1`, or every bootstrap recurses into
  # another bootstrap forever (a real bug this fixed: unbounded
  # ensure_ready! -> seed_room! -> get_active_room_by_slug -> ensure_ready!
  # recursion, observed as an endless "Migrations already up" log flood).
  defp fetch_active_room_by_slug(slug) do
    case SqliteRepo.query!(
           "SELECT #{columns(@room_columns)} FROM family_chat_rooms WHERE slug = ? AND deleted_at IS NULL",
           [slug]
         ) do
      %{rows: [row]} -> room_row(row)
      %{rows: []} -> nil
    end
  end

  @spec list_messages(pos_integer(), pos_integer() | nil, pos_integer() | nil, pos_integer()) ::
          %{nodes: [map()], has_older: boolean(), has_newer: boolean()}
  def list_messages(room_id, before_id, after_id, limit)
      when is_integer(room_id) and is_integer(limit) do
    ensure_ready!()

    cond do
      after_id != nil -> after_page(room_id, after_id, limit)
      before_id != nil -> before_page(room_id, before_id, limit)
      true -> latest_page(room_id, limit)
    end
  end

  @spec find_message(pos_integer(), String.t(), String.t(), String.t()) :: map() | nil
  def find_message(room_id, sender_kind, sender_id, idempotency_key) do
    ensure_ready!()

    case SqliteRepo.query!(
           """
           SELECT #{columns(@message_columns)} FROM family_chat_messages
           WHERE room_id = ? AND sender_kind = ? AND sender_id = ? AND idempotency_key = ?
           """,
           [room_id, sender_kind, sender_id, idempotency_key]
         ) do
      %{rows: [row]} -> message_row(row)
      %{rows: []} -> nil
    end
  end

  @doc """
  Commits a message and, in the same transaction, one pending delivery row for
  every other active Web Push subscription (tech-doc 002's Send Transactions).
  A `sender_kind` of `"system"` includes every active subscription (a system
  sender has no user-owned device to exclude).
  """
  @spec insert_message!(
          pos_integer(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer() | nil
        ) :: {:ok, map()}
  def insert_message!(
        room_id,
        sender_kind,
        sender_id,
        sender_display_name,
        idempotency_key,
        body,
        reply_to_message_id \\ nil
      ) do
    ensure_ready!()

    transaction(fn ->
      now = iso8601(DateTime.utc_now())
      actor = actor_for(sender_kind, sender_id)

      SqliteRepo.query!(
        """
        INSERT INTO family_chat_messages (
          room_id, sender_kind, sender_id, sender_display_name, idempotency_key, body,
          committed_at, created_by, reply_to_message_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          room_id,
          sender_kind,
          sender_id,
          sender_display_name,
          idempotency_key,
          body,
          now,
          actor,
          reply_to_message_id
        ]
      )

      %{rows: [[message_id]]} = SqliteRepo.query!("SELECT last_insert_rowid()")

      deliveries = insert_deliveries!(message_id, sender_kind, sender_id, now, actor)

      message =
        room_id
        |> find_message(sender_kind, sender_id, idempotency_key)
        |> Map.put(:deliveries, deliveries)

      {:ok, message}
    end)
  end

  @doc """
  Resolves the quoted rows for a page of messages in one query, scoped to the
  room that page belongs to.

  Takes the message maps a page returned and gives back a map from quoted
  message id to that row. An id this room has no message for is simply absent
  from the result, and the caller renders such a message as an ordinary one
  rather than raising.

  The room scope is not redundant with `message_by_id/2`'s check at write time.
  That check guards the rows this application writes; this one guards what a
  reader is shown, so a row written any other way can never surface another
  room's text inside this room's page.
  """
  @spec quotes_for(pos_integer(), [map()]) :: %{pos_integer() => map()}
  def quotes_for(room_id, messages) when is_integer(room_id) and is_list(messages) do
    ids =
      messages
      |> Enum.map(& &1[:reply_to_message_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case ids do
      [] ->
        %{}

      ids ->
        ensure_ready!()
        placeholders = Enum.map_join(ids, ", ", fn _ -> "?" end)

        %{rows: rows} =
          SqliteRepo.query!(
            "SELECT #{columns(@message_columns)} FROM family_chat_messages WHERE room_id = ? AND id IN (#{placeholders})",
            [room_id | ids]
          )

        Map.new(rows, fn row ->
          quoted = message_row(row)
          {quoted.id, quoted}
        end)
    end
  end

  @spec message_by_id(pos_integer(), pos_integer()) :: map() | nil
  def message_by_id(room_id, message_id) when is_integer(room_id) and is_integer(message_id) do
    ensure_ready!()

    case SqliteRepo.query!(
           "SELECT #{columns(@message_columns)} FROM family_chat_messages WHERE id = ? AND room_id = ?",
           [message_id, room_id]
         ) do
      %{rows: [row]} -> message_row(row)
      %{rows: []} -> nil
    end
  end

  @spec active_subscription_ids(String.t() | nil) :: [integer()]
  def active_subscription_ids(excluded_user_id) do
    ensure_ready!()

    {sql, params} =
      if excluded_user_id do
        {"SELECT id FROM web_push_subscriptions WHERE deleted_at IS NULL AND user_id != ?",
         [excluded_user_id]}
      else
        {"SELECT id FROM web_push_subscriptions WHERE deleted_at IS NULL", []}
      end

    %{rows: rows} = SqliteRepo.query!(sql, params)
    Enum.map(rows, &hd/1)
  end

  @doc """
  Self-healing bootstrap for every public operation: re-asserts the shared
  `SqliteRepo` connection onto this database, runs pending migrations, and
  (idempotently, via `INSERT OR IGNORE`) reconciles the canonical room and
  retention-schedule seeds. Every public function in this module calls this
  first — the canonical room must exist for any normal read, not only after
  an explicit `:run_family_chat_migration` step.
  """
  @spec ensure_ready!() :: :ok
  def ensure_ready! do
    ensure_started!()
    Ecto.Migrator.run(SqliteRepo, migrations_path(), :up, all: true)
    seed_room!()
    seed_retention_schedule!()
    :ok
  end

  defp ensure_started! do
    # `mix test --no-start` (BE_UNIT/INTEGRATION) never boots any OTP
    # application automatically, including `:ecto_sql`/`:exqlite` — without
    # this, the very first caller in a test run to reach `SqliteRepo` (via
    # this self-healing path, as opposed to the release verifier's own
    # `ensure_database_apps_started!/0`) crashes non-deterministically with
    # "no process" from `Ecto.Repo.Registry`, since it never got started.
    # `Application.ensure_all_started/1` is itself idempotent, so this is
    # cheap on every subsequent call once the apps are already running.
    ensure_database_apps_started!()
    :ok = StorageCoordinator.ensure_started!(database_path())
  end

  defp ensure_database_apps_started! do
    Enum.each([:ecto_sql, :exqlite], fn application ->
      case Application.ensure_all_started(application) do
        {:ok, _started} ->
          :ok

        {:error, {_failed_application, reason}} ->
          raise "could not start #{application}: #{inspect(reason)}"
      end
    end)
  end

  defp database_path do
    Application.get_env(:bnest_app, :family_chat_sqlite_path) ||
      StorageConfig.resolved_database_path()
  end

  defp insert_deliveries!(message_id, sender_kind, sender_id, now, actor) do
    excluded = if sender_kind == "user", do: sender_id, else: nil

    excluded
    |> active_subscription_ids()
    |> Enum.map(fn subscription_id ->
      SqliteRepo.query!(
        """
        INSERT INTO family_chat_push_deliveries (
          message_id, subscription_id, state, attempt_count, next_attempt_at, lease_expires_at,
          failure_category, provider_accepted_at, created_at, created_by, updated_at, updated_by
        ) VALUES (?, ?, 'pending', 0, NULL, NULL, NULL, NULL, ?, ?, ?, ?)
        """,
        [message_id, subscription_id, now, actor, now, actor]
      )

      %{subscription_id: subscription_id, state: "pending"}
    end)
  end

  defp seed_room! do
    now = iso8601(DateTime.utc_now())

    SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO family_chat_rooms (
        id, slug, name, room_kind, member_posting_enabled, created_at, created_by, updated_at, updated_by
      ) VALUES (?, ?, ?, ?, ?, ?, 'system:migration', ?, 'system:migration')
      """,
      [
        @room_seed.id,
        @room_seed.slug,
        @room_seed.name,
        @room_seed.room_kind,
        # `@room_seed.member_posting_enabled` is a fixed compile-time seed
        # constant (always `true`), so this is the literal SQLite boolean
        # encoding (INTEGER 1), not a runtime bool->int helper.
        1,
        now,
        now
      ]
    )

    case fetch_active_room_by_slug(@room_seed.slug) do
      %{id: 1, slug: "ruang-keluarga", name: "Ruang Keluarga"} ->
        :ok

      other ->
        raise "family chat room seed verification failed: #{inspect(other)}"
    end
  end

  defp seed_retention_schedule! do
    now = iso8601(DateTime.utc_now())
    next_run_at = next_daily_slot_iso("17:15", DateTime.utc_now())

    SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO bnest_schedules (
        schedule_key, handler_key, schedule_context, cadence, daily_at_utc, enabled,
        expiration_kind, expires_at, max_occurrences, claimed_occurrences, expired_at,
        next_run_at, revision, inserted_at, updated_at
      ) VALUES (?, 'family_chat_push_retention', 'admin_system', 'daily', '17:15', 0,
                'never', NULL, NULL, 0, NULL, ?, 1, ?, ?)
      """,
      [@retention_schedule_key, next_run_at, now, now]
    )

    :ok
  end

  defp next_daily_slot_iso(daily_at_utc, now) do
    [hour, minute] = daily_at_utc |> String.split(":") |> Enum.map(&String.to_integer/1)
    {:ok, today_slot} = DateTime.new(DateTime.to_date(now), Time.new!(hour, minute, 0), "Etc/UTC")

    next =
      if DateTime.compare(today_slot, now) == :gt,
        do: today_slot,
        else: DateTime.add(today_slot, 86_400)

    iso8601(next)
  end

  defp latest_page(room_id, limit) do
    rows = query_desc(room_id, nil, limit + 1)
    {page, has_older} = split(rows, limit)

    %{
      nodes: page |> Enum.reverse() |> Enum.map(&message_row/1),
      has_older: has_older,
      has_newer: false
    }
  end

  defp before_page(room_id, before_id, limit) do
    rows = query_desc(room_id, before_id, limit + 1)
    {page, has_older} = split(rows, limit)

    %{
      nodes: page |> Enum.reverse() |> Enum.map(&message_row/1),
      has_older: has_older,
      has_newer: true
    }
  end

  defp after_page(room_id, after_id, limit) do
    rows = query_asc(room_id, after_id, limit + 1)
    {page, has_newer} = split(rows, limit)

    %{
      nodes: Enum.map(page, &message_row/1),
      has_older: exists_below?(room_id, after_id),
      has_newer: has_newer
    }
  end

  defp split(rows, limit) do
    if length(rows) > limit, do: {Enum.take(rows, limit), true}, else: {rows, false}
  end

  defp query_desc(room_id, nil, take) do
    %{rows: rows} =
      SqliteRepo.query!(
        "SELECT #{columns(@message_columns)} FROM family_chat_messages WHERE room_id = ? ORDER BY id DESC LIMIT ?",
        [room_id, take]
      )

    rows
  end

  defp query_desc(room_id, before_id, take) do
    %{rows: rows} =
      SqliteRepo.query!(
        """
        SELECT #{columns(@message_columns)} FROM family_chat_messages
        WHERE room_id = ? AND id < ? ORDER BY id DESC LIMIT ?
        """,
        [room_id, before_id, take]
      )

    rows
  end

  defp query_asc(room_id, after_id, take) do
    %{rows: rows} =
      SqliteRepo.query!(
        """
        SELECT #{columns(@message_columns)} FROM family_chat_messages
        WHERE room_id = ? AND id > ? ORDER BY id ASC LIMIT ?
        """,
        [room_id, after_id, take]
      )

    rows
  end

  defp exists_below?(room_id, id) do
    %{rows: [[flag]]} =
      SqliteRepo.query!(
        "SELECT EXISTS(SELECT 1 FROM family_chat_messages WHERE room_id = ? AND id < ?)",
        [room_id, id]
      )

    flag == 1
  end

  defp actor_for("system", sender_id), do: "system:" <> sender_id
  defp actor_for(_user_kind, sender_id), do: "user:" <> sender_id

  defp room_row(row) do
    @room_columns
    |> Enum.zip(row)
    |> Map.new()
    |> Map.update!(:member_posting_enabled, &(&1 == 1))
    |> Map.update!(:created_at, &parse_datetime/1)
    |> Map.update!(:updated_at, &parse_datetime/1)
  end

  defp message_row(row) do
    @message_columns
    |> Enum.zip(row)
    |> Map.new()
    |> Map.update!(:committed_at, &parse_datetime/1)
  end

  defp columns(fields), do: Enum.map_join(fields, ", ", &to_string/1)
  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp parse_datetime(value), do: DateTime.from_iso8601(value) |> elem(1)
  defp migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

  defp transaction(fun) do
    case SqliteRepo.transaction(fun, mode: :immediate) do
      {:ok, value} -> value
      {:error, reason} -> raise "family chat transaction failed: #{inspect(reason)}"
    end
  end
end
