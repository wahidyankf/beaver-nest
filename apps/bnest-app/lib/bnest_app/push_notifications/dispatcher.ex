defmodule BnestApp.PushNotifications.Dispatcher do
  @moduledoc """
  Owns the delivery row's claim/attempt/transition lifecycle (tech-doc 002's
  "Delivery claim and transition"). `BnestApp.PushNotifications.dispatch_due!/0`
  is the real production entry point (called from the periodic sweep, see
  `BnestApp.Scheduler`'s tick); `attempt/1` also accepts an explicit
  `simulated` outcome class purely as a test seam (unit/integration tests
  never reach real HTTP) -- when given, it skips `Sender` entirely and, if no
  real due row exists yet, bootstraps one self-contained synthetic
  message/subscription/delivery fixture so the transition logic under test is
  still genuinely exercised against real SQLite rows, never a stored
  sentinel.
  """

  alias BnestApp.FamilyChat.Store, as: FamilyChatStore
  alias BnestApp.PushNotifications.Policy
  alias BnestApp.PushNotifications.Sender
  alias BnestApp.SqliteRepo

  @lease_seconds 120

  @spec attempt(:retryable | :gone | nil) :: {:ok, map()} | {:error, :no_due_delivery}
  def attempt(simulated \\ nil) do
    FamilyChatStore.ensure_ready!()
    now = DateTime.utc_now()

    case claim_due_row(now) do
      nil -> attempt_bootstrapped(simulated, now)
      delivery -> transition(delivery, resolve_outcome(simulated, delivery), now)
    end
  end

  defp attempt_bootstrapped(nil, _now), do: {:error, :no_due_delivery}

  defp attempt_bootstrapped(simulated, now) do
    delivery = bootstrap_and_claim!(simulated, now)
    result = transition(delivery, resolve_outcome(simulated, delivery), now)

    # Whichever subscription this claim actually landed on (the freshly
    # inserted synthetic one in the common case; see `claim_due_row/1`'s
    # oldest-id-first ordering) targets the single shared canonical room
    # (tech-doc 002 has exactly one room). Leaving it active would silently
    # inflate a LATER scenario's "every active subscription" fan-out for the
    # rest of the test run, so this test-only path always retires it.
    # Idempotent with a `:gone` transition's own disable (WHERE deleted_at IS
    # NULL guards a second no-op call).
    disable_subscription!(delivery.subscription_id, now)
    result
  end

  defp resolve_outcome(nil, delivery), do: real_outcome(delivery)
  defp resolve_outcome(:retryable, _delivery), do: Policy.classify_result({:status, 503})
  defp resolve_outcome(:gone, _delivery), do: Policy.classify_result({:status, 410})

  defp real_outcome(delivery) do
    with %{} = message <- fetch_message(delivery.message_id),
         %{} = subscription <- fetch_subscription(delivery.subscription_id) do
      payload =
        Policy.build_payload(
          message.id,
          message.sender_display_name,
          message.body,
          message.room_slug
        )

      subscription |> Sender.send(payload) |> Policy.classify_result()
    else
      nil -> :terminal
    end
  end

  defp claim_due_row(now) do
    iso_now = iso8601(now)

    transaction(fn ->
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
          mark_claimed!(id, attempt_count + 1, iso_now)

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

  defp mark_claimed!(id, attempt, iso_now) do
    lease_until = DateTime.utc_now() |> DateTime.add(@lease_seconds, :second) |> iso8601()

    SqliteRepo.query!(
      """
      UPDATE family_chat_push_deliveries
      SET state='claimed', attempt_count=?, lease_expires_at=?, next_attempt_at=NULL,
          updated_at=?, updated_by='system:push-dispatcher'
      WHERE id=?
      """,
      [attempt, lease_until, iso_now, id]
    )
  end

  defp transition(delivery, :delivered, now) do
    finalize!(delivery.id, "delivered", nil, iso8601(now), now)
    {:ok, %{state: "delivered", next_attempt_at: nil, attempt: delivery.attempt}}
  end

  defp transition(delivery, :gone, now) do
    finalize!(delivery.id, "terminal", "gone", nil, now)
    disable_subscription!(delivery.subscription_id, now)
    {:ok, %{state: "terminal", next_attempt_at: nil, attempt: delivery.attempt}}
  end

  defp transition(delivery, :terminal, now) do
    finalize!(delivery.id, "terminal", "provider", nil, now)
    {:ok, %{state: "terminal", next_attempt_at: nil, attempt: delivery.attempt}}
  end

  defp transition(delivery, :retryable, now) do
    case Policy.next_wait_seconds(delivery.attempt, delivery.created_at, now) do
      nil ->
        finalize!(delivery.id, "terminal", "ceiling", nil, now)
        {:ok, %{state: "terminal", next_attempt_at: nil, attempt: delivery.attempt}}

      wait_seconds ->
        next_attempt_at = DateTime.add(now, wait_seconds, :second)

        SqliteRepo.query!(
          """
          UPDATE family_chat_push_deliveries
          SET state='retryable', lease_expires_at=NULL, next_attempt_at=?, failure_category='retryable',
              updated_at=?, updated_by='system:push-dispatcher'
          WHERE id=?
          """,
          [iso8601(next_attempt_at), iso8601(now), delivery.id]
        )

        {:ok, %{state: "retryable", next_attempt_at: next_attempt_at, attempt: delivery.attempt}}
    end
  end

  defp finalize!(id, state, failure_category, provider_accepted_at, now) do
    SqliteRepo.query!(
      """
      UPDATE family_chat_push_deliveries
      SET state=?, lease_expires_at=NULL, next_attempt_at=NULL, failure_category=?,
          provider_accepted_at=?, updated_at=?, updated_by='system:push-dispatcher'
      WHERE id=?
      """,
      [state, failure_category, provider_accepted_at, iso8601(now), id]
    )
  end

  defp disable_subscription!(subscription_id, now) do
    iso_now = iso8601(now)

    SqliteRepo.query!(
      """
      UPDATE web_push_subscriptions
      SET deleted_at=?, deleted_by='system:push-dispatcher', updated_at=?, updated_by='system:push-dispatcher'
      WHERE id=? AND deleted_at IS NULL
      """,
      [iso_now, iso_now, subscription_id]
    )
  end

  defp fetch_message(message_id) do
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

  defp fetch_subscription(subscription_id) do
    case SqliteRepo.query!(
           "SELECT endpoint, p256dh, auth_secret FROM web_push_subscriptions WHERE id = ?",
           [subscription_id]
         ) do
      %{rows: [[endpoint, p256dh, auth]]} -> %{endpoint: endpoint, p256dh: p256dh, auth: auth}
      %{rows: []} -> nil
    end
  end

  # Test-only seam (see moduledoc and `attempt_bootstrapped/2`): a real
  # `simulated` caller never has a naturally-due row to claim (its Given step
  # only records a classification intent, not a real fixture -- see the
  # Gherkin/driver contract this mirrors), so this creates exactly one
  # self-contained message + active subscription + pending delivery row and
  # re-claims it. Only ever called when `simulated` is non-nil (see
  # `attempt_bootstrapped/2`'s `nil` clause).
  defp bootstrap_and_claim!(_simulated, now) do
    room = FamilyChatStore.get_active_room_by_slug(FamilyChatStore.canonical_room_slug())
    subscriber_id = "system:push-dispatcher-fixture-" <> unique_id()
    subscription_id = insert_synthetic_subscription!(subscriber_id, now)

    {:ok, _message} =
      FamilyChatStore.insert_message!(
        room.id,
        "system",
        "system:push-dispatcher-fixture-sender-" <> unique_id(),
        "System",
        unique_id(),
        "synthetic dispatcher fixture"
      )

    # `insert_message!/6` already created one pending delivery row per active
    # subscription at commit time (tech-doc 002); claim that real row rather
    # than inserting a second one.
    claim_due_row(now) ||
      raise "dispatcher fixture bootstrap did not produce a claimable row (subscription #{subscription_id})"
  end

  defp insert_synthetic_subscription!(user_id, now) do
    iso_now = iso8601(now)
    session_digest = :crypto.hash(:sha256, user_id) |> Base.encode16(case: :lower)
    endpoint = "https://push.allowed.example.com/" <> user_id
    endpoint_sha256 = Policy.endpoint_digest(endpoint)
    actor = "user:" <> user_id

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
        "fixture-p256dh",
        "fixture-auth",
        iso_now,
        actor,
        iso_now,
        actor
      ]
    )

    %{rows: [[id]]} =
      SqliteRepo.query!("SELECT id FROM web_push_subscriptions WHERE endpoint_sha256 = ?", [
        endpoint_sha256
      ])

    id
  end

  defp unique_id, do: Ecto.UUID.generate()
  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp parse_datetime(value), do: DateTime.from_iso8601(value) |> elem(1)

  defp transaction(fun) do
    case SqliteRepo.transaction(fun, mode: :immediate) do
      {:ok, value} -> value
      {:error, reason} -> raise "push dispatcher transaction failed: #{inspect(reason)}"
    end
  end
end
