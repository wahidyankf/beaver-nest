defmodule BnestApp.PushNotifications.Adapters.SqliteDeliveryStore do
  @moduledoc """
  The `BnestApp.PushNotifications.Ports.DeliveryStore` over the
  `family_chat_push_deliveries` table in Family Chat's SQLite database (with the message
  and room tables it reads payloads from): raw SQL through the shared `SqliteRepo`, audit
  columns written explicitly.

  The tables live in Family Chat's database, so the caller first prepares that database
  through `BnestApp.FamilyChat.ensure_ready!/0`, which also repoints the shared connection
  onto it; this adapter assumes it has.
  """

  @behaviour BnestApp.PushNotifications.Ports.DeliveryStore

  alias BnestApp.SqliteRepo

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def claim_due(_store, now, lease_until) do
    iso_now = iso8601(now)

    in_transaction("push dispatcher", fn ->
      case SqliteRepo.query!(
             """
             SELECT id, message_id, subscription_id, attempt_count, created_at
             FROM family_chat_push_deliveries
             WHERE deleted_at IS NULL AND (
               (state IN ('pending','retryable') AND (next_attempt_at IS NULL OR next_attempt_at <= ?))
               OR (state = 'claimed' AND lease_expires_at <= ?)
             )
             ORDER BY id LIMIT 1
             """,
             [iso_now, iso_now]
           ) do
        %{rows: []} ->
          nil

        %{rows: [[id, message_id, subscription_id, attempt_count, created_at]]} ->
          SqliteRepo.query!(
            """
            UPDATE family_chat_push_deliveries
            SET state='claimed', attempt_count=?, lease_expires_at=?, next_attempt_at=NULL,
                updated_at=?, updated_by='system:push-dispatcher'
            WHERE id=?
            """,
            [attempt_count + 1, iso8601(lease_until), iso_now, id]
          )

          %{
            id: id,
            message_id: message_id,
            subscription_id: subscription_id,
            attempt: attempt_count + 1,
            created_at: parse_datetime(created_at)
          }
      end
    end)
  end

  @impl true
  def retry!(_store, delivery_id, next_attempt_at, now) do
    SqliteRepo.query!(
      """
      UPDATE family_chat_push_deliveries
      SET state='retryable', lease_expires_at=NULL, next_attempt_at=?, failure_category='retryable',
          updated_at=?, updated_by='system:push-dispatcher'
      WHERE id=?
      """,
      [iso8601(next_attempt_at), iso8601(now), delivery_id]
    )

    :ok
  end

  @impl true
  def finalize!(_store, delivery_id, state, failure_category, provider_accepted_at, now) do
    SqliteRepo.query!(
      """
      UPDATE family_chat_push_deliveries
      SET state=?, lease_expires_at=NULL, next_attempt_at=NULL, failure_category=?,
          provider_accepted_at=?, updated_at=?, updated_by='system:push-dispatcher'
      WHERE id=?
      """,
      [state, failure_category, iso8601_or_nil(provider_accepted_at), iso8601(now), delivery_id]
    )

    :ok
  end

  @impl true
  def message(_store, message_id) do
    case SqliteRepo.query!(
           """
           SELECT m.id, m.body, m.sender_display_name, r.slug
           FROM family_chat_messages m JOIN family_chat_rooms r ON r.id = m.room_id
           WHERE m.id = ?
           """,
           [message_id]
         ) do
      %{rows: [[id, body, sender_display_name, slug]]} ->
        %{id: id, body: body, sender_display_name: sender_display_name, room_slug: slug}

      %{rows: []} ->
        nil
    end
  end

  # `limit` is interpolated into the text, as the batch size always was, so the statement
  # is unchanged; the guard admits only a positive integer into it.
  @impl true
  def soft_delete_final!(_store, cutoff, now, limit) when is_integer(limit) and limit > 0 do
    %{num_rows: count} =
      SqliteRepo.query!(
        """
        UPDATE family_chat_push_deliveries
        SET deleted_at=?, deleted_by='system:push-retention'
        WHERE id IN (
          SELECT id FROM family_chat_push_deliveries
          WHERE deleted_at IS NULL AND state IN ('delivered','terminal') AND updated_at <= ?
          ORDER BY id LIMIT #{limit}
        )
        """,
        [iso8601(now), iso8601(cutoff)]
      )

    count
  end

  @impl true
  def purge_deleted!(_store, cutoff, limit) when is_integer(limit) and limit > 0 do
    %{num_rows: count} =
      SqliteRepo.query!(
        """
        DELETE FROM family_chat_push_deliveries
        WHERE id IN (
          SELECT id FROM family_chat_push_deliveries
          WHERE deleted_at IS NOT NULL AND deleted_at <= ?
          ORDER BY id LIMIT #{limit}
        )
        """,
        [iso8601(cutoff)]
      )

    count
  end

  @impl true
  def count_active_unfinished(_store) do
    %{rows: [[count]]} =
      SqliteRepo.query!(
        "SELECT COUNT(*) FROM family_chat_push_deliveries WHERE deleted_at IS NULL AND state IN ('pending','claimed','retryable')"
      )

    count
  end

  @impl true
  def transaction(_store, fun), do: in_transaction("push notifications", fun)

  defp in_transaction(owner, fun) do
    case SqliteRepo.transaction(fun, mode: :immediate) do
      {:ok, value} -> value
      {:error, reason} -> raise "#{owner} transaction failed: #{inspect(reason)}"
    end
  end

  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp iso8601_or_nil(nil), do: nil
  defp iso8601_or_nil(value), do: iso8601(value)

  defp parse_datetime(value), do: DateTime.from_iso8601(value) |> elem(1)
end
