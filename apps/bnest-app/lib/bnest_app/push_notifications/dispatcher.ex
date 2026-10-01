defmodule BnestApp.PushNotifications.Dispatcher do
  @moduledoc """
  Owns the delivery's claim/attempt/transition lifecycle (tech-doc 002's
  "Delivery claim and transition"). `BnestApp.PushNotifications.dispatch_all_due!/0`
  is the production entry point (called from the periodic sweep, see
  `BnestApp.Scheduler`'s tick).

  Each `attempt/0` claims the due delivery with the lowest ID through the configured
  `Ports.DeliveryStore`, sends its message to its subscription through the configured
  `Ports.PushSender`, and records the transition `Domain.Policy` classifies the outcome
  as, disabling a subscription the provider reports gone.
  """

  alias BnestApp.FamilyChat
  alias BnestApp.PushNotifications
  alias BnestApp.PushNotifications.Domain.Policy
  alias BnestApp.PushNotifications.Ports.DeliveryStore
  alias BnestApp.PushNotifications.Ports.SubscriptionStore

  @lease_seconds 120

  @spec attempt() :: {:ok, map()} | {:error, :no_due_delivery}
  def attempt do
    FamilyChat.ensure_ready!()
    now = DateTime.utc_now()
    deliveries = PushNotifications.adapter(:delivery_store).new()
    subscriptions = PushNotifications.adapter(:subscription_store).new()

    case DeliveryStore.claim_due(deliveries, now, DateTime.add(now, @lease_seconds, :second)) do
      nil ->
        {:error, :no_due_delivery}

      delivery ->
        outcome = outcome(deliveries, subscriptions, delivery)
        transition(deliveries, subscriptions, delivery, outcome, now)
    end
  end

  defp outcome(deliveries, subscriptions, delivery) do
    with %{} = message <- DeliveryStore.message(deliveries, delivery.message_id),
         %{} = subscription <- SubscriptionStore.fetch(subscriptions, delivery.subscription_id) do
      payload =
        Policy.build_payload(
          message.id,
          message.sender_display_name,
          message.body,
          message.room_slug
        )

      PushNotifications.adapter(:push_sender).send(subscription, payload)
      |> Policy.classify_result()
    else
      nil -> :terminal
    end
  end

  defp transition(deliveries, _subscriptions, delivery, :delivered, now) do
    :ok = DeliveryStore.finalize!(deliveries, delivery.id, "delivered", nil, now, now)
    {:ok, %{state: "delivered", next_attempt_at: nil, attempt: delivery.attempt}}
  end

  defp transition(deliveries, subscriptions, delivery, :gone, now) do
    :ok = DeliveryStore.finalize!(deliveries, delivery.id, "terminal", "gone", nil, now)
    :ok = SubscriptionStore.disable_gone!(subscriptions, delivery.subscription_id, now)
    {:ok, %{state: "terminal", next_attempt_at: nil, attempt: delivery.attempt}}
  end

  defp transition(deliveries, _subscriptions, delivery, :terminal, now) do
    :ok = DeliveryStore.finalize!(deliveries, delivery.id, "terminal", "provider", nil, now)
    {:ok, %{state: "terminal", next_attempt_at: nil, attempt: delivery.attempt}}
  end

  defp transition(deliveries, _subscriptions, delivery, :retryable, now) do
    case Policy.next_wait_seconds(delivery.attempt, delivery.created_at, now) do
      nil ->
        :ok = DeliveryStore.finalize!(deliveries, delivery.id, "terminal", "ceiling", nil, now)
        {:ok, %{state: "terminal", next_attempt_at: nil, attempt: delivery.attempt}}

      wait_seconds ->
        next_attempt_at = DateTime.add(now, wait_seconds, :second)
        :ok = DeliveryStore.retry!(deliveries, delivery.id, next_attempt_at, now)
        {:ok, %{state: "retryable", next_attempt_at: next_attempt_at, attempt: delivery.attempt}}
    end
  end
end
