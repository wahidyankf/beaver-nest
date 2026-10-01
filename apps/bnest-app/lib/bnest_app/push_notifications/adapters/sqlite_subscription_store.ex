defmodule BnestApp.PushNotifications.Adapters.SqliteSubscriptionStore do
  @moduledoc """
  The `BnestApp.PushNotifications.Ports.SubscriptionStore` over the
  `web_push_subscriptions` table in Family Chat's SQLite database: raw SQL through the
  shared `SqliteRepo`, audit columns written explicitly.

  The table lives in Family Chat's database, so the caller first prepares that database
  through `BnestApp.FamilyChat.ensure_ready!/0`, which also repoints the shared connection
  onto it; this adapter assumes it has.
  """

  @behaviour BnestApp.PushNotifications.Ports.SubscriptionStore

  alias BnestApp.SqliteRepo

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def active_subscription(_store, user_id, session_digest) do
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

  @impl true
  def upsert!(_store, user_id, session_digest, binding, now) do
    transaction(fn -> do_upsert!(user_id, session_digest, binding, iso8601(now)) end)
  end

  @impl true
  def disable_session!(_store, user_id, session_digest, now) do
    now = iso8601(now)
    actor = "user:" <> to_string(user_id)

    SqliteRepo.query!(
      """
      UPDATE web_push_subscriptions
      SET deleted_at=?, deleted_by=?, updated_at=?, updated_by=?
      WHERE user_id=? AND session_digest=? AND deleted_at IS NULL
      """,
      [now, actor, now, actor, user_id, session_digest]
    )

    :ok
  end

  @impl true
  def disable_gone!(_store, subscription_id, now) do
    iso_now = iso8601(now)

    SqliteRepo.query!(
      """
      UPDATE web_push_subscriptions
      SET deleted_at=?, deleted_by='system:push-dispatcher', updated_at=?, updated_by='system:push-dispatcher'
      WHERE id=? AND deleted_at IS NULL
      """,
      [iso_now, iso_now, subscription_id]
    )

    :ok
  end

  @impl true
  def fetch(_store, subscription_id) do
    case SqliteRepo.query!(
           "SELECT endpoint, p256dh, auth_secret FROM web_push_subscriptions WHERE id = ?",
           [subscription_id]
         ) do
      %{rows: [[endpoint, p256dh, auth]]} -> %{endpoint: endpoint, p256dh: p256dh, auth: auth}
      %{rows: []} -> nil
    end
  end

  defp do_upsert!(user_id, session_digest, binding, now) do
    %{endpoint: endpoint, endpoint_sha256: endpoint_sha256, p256dh: p256dh, auth: auth} =
      binding

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

  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp transaction(fun) do
    case SqliteRepo.transaction(fun, mode: :immediate) do
      {:ok, value} -> value
      {:error, reason} -> raise "push notifications transaction failed: #{inspect(reason)}"
    end
  end
end
