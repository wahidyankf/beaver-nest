defmodule BnestApp.PushNotifications do
  @moduledoc """
  Public Web Push context (tech-doc 004/002). Owns subscription CRUD SQL and
  the Delivery Retention batch algorithm ("The public Push Notifications
  service fixes cutoffs once per run; the Scheduler handler contains no
  family-chat SQL" -- tech-doc 002). `Dispatcher` owns the delivery
  claim/attempt/transition lifecycle and lives alongside this module rather
  than inside it, since it is the one place performing egress.
  """

  alias BnestApp.FamilyChat.Store, as: FamilyChatStore
  alias BnestApp.PushNotifications.Dispatcher
  alias BnestApp.PushNotifications.Policy
  alias BnestApp.SqliteRepo

  @retention_days 7
  @batch_size 250

  @spec configuration() :: {:ok, %{available: boolean(), public_key: String.t() | nil}}
  def configuration do
    {:ok, %{available: vapid_configured?(), public_key: vapid_public_key()}}
  end

  @spec current_subscription(String.t() | nil, String.t()) :: {:ok, map()}
  def current_subscription(user_id, session_key) do
    FamilyChatStore.ensure_ready!()

    case active_row(user_id, digest_session(session_key)) do
      %{expiration_time: expiration_time} ->
        {:ok, %{enabled: true, expiration_time: expiration_time}}

      nil ->
        {:ok, %{enabled: false, expiration_time: nil}}
    end
  end

  @spec upsert_subscription(String.t() | nil, String.t(), map()) ::
          {:ok, %{enabled: true, expiration_time: nil}} | {:error, map()}
  def upsert_subscription(user_id, session_key, input) when is_binary(user_id) do
    FamilyChatStore.ensure_ready!()

    case Policy.validate_subscription_input(input) do
      {:ok, validated} ->
        transaction(fn -> do_upsert!(user_id, digest_session(session_key), validated) end)
        {:ok, %{enabled: true, expiration_time: nil}}

      {:error, _reason} ->
        {:error, %{code: "VALIDATION_FAILED", details: nil}}
    end
  end

  def upsert_subscription(nil, _session_key, _input),
    do: {:error, %{code: "UNAUTHENTICATED", details: nil}}

  @spec disable_subscription(String.t() | nil, String.t()) :: {:ok, %{enabled: false}}
  def disable_subscription(user_id, session_key) do
    FamilyChatStore.ensure_ready!()
    now = iso8601(DateTime.utc_now())
    actor = "user:" <> to_string(user_id)

    SqliteRepo.query!(
      """
      UPDATE web_push_subscriptions
      SET deleted_at=?, deleted_by=?, updated_at=?, updated_by=?
      WHERE user_id=? AND session_digest=? AND deleted_at IS NULL
      """,
      [now, actor, now, actor, user_id, digest_session(session_key)]
    )

    {:ok, %{enabled: false}}
  end

  @doc "Drains every currently-due delivery via `Dispatcher.attempt/1`, one row at a time, until none remain. The real production dispatch trigger (see `BnestApp.Scheduler`'s tick, which calls this once per 60s tick alongside the daily-cadence sweep)."
  @spec dispatch_all_due!() :: :ok
  def dispatch_all_due! do
    case Dispatcher.attempt(nil) do
      {:ok, _transition} -> dispatch_all_due!()
      {:error, :no_due_delivery} -> :ok
    end
  end

  @doc "Tech-doc 002's Delivery Retention algorithm: fixes `active_cutoff`/`purge_cutoff` from one injected instant, soft-deletes final rows older than 7 elapsed days in ascending-ID batches, purges rows soft-deleted for 7 more elapsed days, and reports non-final rows only as an aggregate count (never age-purged)."
  @spec retain_deliveries(DateTime.t()) ::
          {:ok,
           %{
             soft_deleted: non_neg_integer(),
             purged: non_neg_integer(),
             remaining_active: non_neg_integer()
           }}
  def retain_deliveries(%DateTime{} = now) do
    FamilyChatStore.ensure_ready!()
    active_cutoff = now |> DateTime.add(-@retention_days * 86_400, :second) |> iso8601()
    purge_cutoff = now |> DateTime.add(-@retention_days * 86_400, :second) |> iso8601()
    now_iso = iso8601(now)

    transaction(fn ->
      soft_deleted = soft_delete_all!(active_cutoff, now_iso, 0)
      purged = purge_all!(purge_cutoff, 0)
      remaining_active = count_nonfinal!()
      {:ok, %{soft_deleted: soft_deleted, purged: purged, remaining_active: remaining_active}}
    end)
  end

  defp active_row(user_id, session_digest) do
    case SqliteRepo.query!(
           """
           SELECT expiration_time FROM web_push_subscriptions
           WHERE user_id=? AND session_digest=? AND deleted_at IS NULL
           ORDER BY id DESC LIMIT 1
           """,
           [user_id, session_digest]
         ) do
      %{rows: [[expiration_time]]} -> %{expiration_time: expiration_time}
      %{rows: []} -> nil
    end
  end

  defp do_upsert!(user_id, session_digest, %{endpoint: endpoint, p256dh: p256dh, auth: auth}) do
    endpoint_sha256 = Policy.endpoint_digest(endpoint)
    now = iso8601(DateTime.utc_now())
    actor = "user:" <> user_id

    # Deactivate any other active binding for this exact (user, session) pair
    # first (tech-doc 002: "soft-deactivate any other active binding for
    # (user_id, session_digest), then insert/reactivate the validated
    # endpoint"), so a device that re-subscribes with a new endpoint never
    # leaves two active rows racing for the same delivery fan-out.
    SqliteRepo.query!(
      """
      UPDATE web_push_subscriptions
      SET deleted_at=?, deleted_by=?, updated_at=?, updated_by=?
      WHERE user_id=? AND session_digest=? AND endpoint_sha256 != ? AND deleted_at IS NULL
      """,
      [now, actor, now, actor, user_id, session_digest, endpoint_sha256]
    )

    case SqliteRepo.query!("SELECT id FROM web_push_subscriptions WHERE endpoint_sha256=?", [
           endpoint_sha256
         ]) do
      %{rows: [[id]]} ->
        # Reactivate/rebind: endpoint ownership moving between users is
        # explicit rebind behavior, never inferred (tech-doc 002).
        SqliteRepo.query!(
          """
          UPDATE web_push_subscriptions
          SET user_id=?, session_digest=?, p256dh=?, auth_secret=?,
              deleted_at=NULL, deleted_by=NULL, updated_at=?, updated_by=?
          WHERE id=?
          """,
          [user_id, session_digest, p256dh, auth, now, actor, id]
        )

      %{rows: []} ->
        SqliteRepo.query!(
          """
          INSERT INTO web_push_subscriptions (
            user_id, session_digest, endpoint_sha256, endpoint, p256dh, auth_secret,
            expiration_time, created_at, created_by, updated_at, updated_by
          ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
          """,
          [
            user_id,
            session_digest,
            endpoint_sha256,
            endpoint,
            p256dh,
            auth,
            now,
            actor,
            now,
            actor
          ]
        )
    end

    :ok
  end

  defp soft_delete_all!(active_cutoff, now_iso, total) do
    result =
      SqliteRepo.query!(
        """
        UPDATE family_chat_push_deliveries
        SET deleted_at=?, deleted_by='system:push-retention'
        WHERE id IN (
          SELECT id FROM family_chat_push_deliveries
          WHERE deleted_at IS NULL AND state IN ('delivered','terminal') AND updated_at <= ?
          ORDER BY id LIMIT #{@batch_size}
        )
        """,
        [now_iso, active_cutoff]
      )

    if result.num_rows > 0,
      do: soft_delete_all!(active_cutoff, now_iso, total + result.num_rows),
      else: total
  end

  defp purge_all!(purge_cutoff, total) do
    result =
      SqliteRepo.query!(
        """
        DELETE FROM family_chat_push_deliveries
        WHERE id IN (
          SELECT id FROM family_chat_push_deliveries
          WHERE deleted_at IS NOT NULL AND deleted_at <= ?
          ORDER BY id LIMIT #{@batch_size}
        )
        """,
        [purge_cutoff]
      )

    if result.num_rows > 0, do: purge_all!(purge_cutoff, total + result.num_rows), else: total
  end

  defp count_nonfinal! do
    %{rows: [[count]]} =
      SqliteRepo.query!(
        "SELECT COUNT(*) FROM family_chat_push_deliveries WHERE deleted_at IS NULL AND state IN ('pending','claimed','retryable')"
      )

    count
  end

  defp vapid_configured? do
    match?({_public, _private, _subject}, vapid_keys())
  end

  defp vapid_public_key do
    case vapid_keys() do
      {public, _private, _subject} -> public
      nil -> nil
    end
  end

  # Reads the exact same `:web_push, :vapid` config `WebPush.Vapid` itself
  # reads (see `config/runtime.exs`), so availability reporting can never
  # drift from what `PushNotifications.Sender` actually signs with.
  defp vapid_keys do
    case Application.get_env(:web_push, :vapid) do
      cfg when is_list(cfg) or is_map(cfg) ->
        public = get_cfg(cfg, :public_key)
        private = get_cfg(cfg, :private_key)
        subject = get_cfg(cfg, :subject)

        if is_binary(public) and is_binary(private) and is_binary(subject),
          do: {public, private, subject},
          else: nil

      _unset ->
        nil
    end
  end

  defp get_cfg(cfg, key) when is_list(cfg), do: Keyword.get(cfg, key)
  defp get_cfg(cfg, key) when is_map(cfg), do: Map.get(cfg, key)

  # The `web_push_subscriptions.session_digest` column is CHECK-constrained
  # to exactly 64 hex characters. Every caller here (the GraphQL resolver in
  # production; the unit/integration test drivers) passes a per-session
  # discriminator string, not necessarily a value already shaped like a
  # SHA-256 hex digest -- this is the one place that actually derives the
  # stored digest, so storage/lookup can never depend on a caller having
  # pre-hashed correctly. Mirrors the same one-way hash the unit driver's own
  # `create_active_subscription!/1` fixture applies independently.
  defp digest_session(session_key) when is_binary(session_key),
    do: :crypto.hash(:sha256, session_key) |> Base.encode16(case: :lower)

  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp transaction(fun) do
    case SqliteRepo.transaction(fun, mode: :immediate) do
      {:ok, value} -> value
      {:error, reason} -> raise "push notifications transaction failed: #{inspect(reason)}"
    end
  end
end
