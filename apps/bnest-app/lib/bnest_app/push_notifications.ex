defmodule BnestApp.PushNotifications do
  @moduledoc """
  The Push Notifications bounded context: Web Push subscriptions, the family chat
  deliveries owed to them, and their retention (tech-docs 004/002).

  This module is the context's application-service facade: the GraphQL resolver, Identity's
  subscription revoker, the Scheduler's tick and the retention task call only this module.
  Its adapters come from application configuration under
  `config :bnest_app, BnestApp.PushNotifications`, one per port in
  `BnestApp.PushNotifications.Ports` (`:subscription_store`, `:delivery_store` and
  `:push_sender`), so a unit test can supply in-memory doubles. Validation and payload
  rules are the pure `BnestApp.PushNotifications.Domain.Policy`. `Dispatcher` owns the
  delivery claim/attempt/transition lifecycle, the one place performing egress; this module
  runs the Delivery Retention batch algorithm ("The public Push Notifications service fixes
  cutoffs once per run; the Scheduler handler contains no family-chat SQL" -- tech-doc
  002).

  Both stores keep their tables in Family Chat's database, so every operation first
  prepares it through `BnestApp.FamilyChat.ensure_ready!/0`.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.FamilyChat],
    exports: [{Domain, []}, {Ports, []}]

  alias BnestApp.FamilyChat
  alias BnestApp.PushNotifications.Dispatcher
  alias BnestApp.PushNotifications.Domain.Policy
  alias BnestApp.PushNotifications.Ports.DeliveryStore
  alias BnestApp.PushNotifications.Ports.SubscriptionStore

  @retention_days 7
  @batch_size 250

  @doc """
  The configured adapter for a Push Notifications port: `:subscription_store`,
  `:delivery_store` or `:push_sender`.
  """
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @spec configuration() :: {:ok, %{available: boolean(), public_key: String.t() | nil}}
  def configuration do
    {:ok, %{available: vapid_configured?(), public_key: vapid_public_key()}}
  end

  @spec current_subscription(String.t() | nil, String.t()) :: {:ok, map()}
  def current_subscription(user_id, session_key) do
    FamilyChat.ensure_ready!()

    case SubscriptionStore.active_subscription(
           subscriptions(),
           user_id,
           digest_session(session_key)
         ) do
      %{expiration_time: expiration_time} ->
        {:ok, %{enabled: true, expiration_time: expiration_time}}

      nil ->
        {:ok, %{enabled: false, expiration_time: nil}}
    end
  end

  @spec upsert_subscription(String.t() | nil, String.t(), map()) ::
          {:ok, %{enabled: true, expiration_time: nil}} | {:error, map()}
  def upsert_subscription(user_id, session_key, input) when is_binary(user_id) do
    FamilyChat.ensure_ready!()

    # Only the synthetic hosts of a sender that never dials out join the production
    # allowlist (see `Ports.PushSender`).
    case Policy.validate_subscription_input(
           input,
           adapter(:push_sender).synthetic_provider_hosts()
         ) do
      {:ok, %{endpoint: endpoint, p256dh: p256dh, auth: auth}} ->
        binding = %{
          endpoint: endpoint,
          endpoint_sha256: Policy.endpoint_digest(endpoint),
          p256dh: p256dh,
          auth: auth
        }

        :ok =
          SubscriptionStore.upsert!(
            subscriptions(),
            user_id,
            digest_session(session_key),
            binding,
            DateTime.utc_now()
          )

        {:ok, %{enabled: true, expiration_time: nil}}

      {:error, _reason} ->
        {:error, %{code: "VALIDATION_FAILED", details: nil}}
    end
  end

  def upsert_subscription(nil, _session_key, _input),
    do: {:error, %{code: "UNAUTHENTICATED", details: nil}}

  @spec disable_subscription(String.t() | nil, String.t()) :: {:ok, %{enabled: false}}
  def disable_subscription(user_id, session_key) do
    FamilyChat.ensure_ready!()

    :ok =
      SubscriptionStore.disable_session!(
        subscriptions(),
        user_id,
        digest_session(session_key),
        DateTime.utc_now()
      )

    {:ok, %{enabled: false}}
  end

  @doc "Drains every currently-due delivery via `Dispatcher.attempt/0`, one row at a time, until none remain. The real production dispatch trigger (see `BnestApp.Scheduler`'s tick, which calls this once per 60s tick alongside the daily-cadence sweep)."
  @spec dispatch_all_due!() :: :ok
  def dispatch_all_due! do
    case Dispatcher.attempt() do
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
    FamilyChat.ensure_ready!()
    active_cutoff = DateTime.add(now, -@retention_days * 86_400, :second)
    purge_cutoff = DateTime.add(now, -@retention_days * 86_400, :second)
    store = deliveries()

    DeliveryStore.transaction(store, fn ->
      soft_deleted =
        drain(fn -> DeliveryStore.soft_delete_final!(store, active_cutoff, now, @batch_size) end)

      purged = drain(fn -> DeliveryStore.purge_deleted!(store, purge_cutoff, @batch_size) end)
      remaining_active = DeliveryStore.count_active_unfinished(store)
      {:ok, %{soft_deleted: soft_deleted, purged: purged, remaining_active: remaining_active}}
    end)
  end

  # Repeats one batch until a batch changes no row; returns how many rows changed in all.
  defp drain(batch, total \\ 0) do
    case batch.() do
      0 -> total
      count -> drain(batch, total + count)
    end
  end

  defp subscriptions, do: adapter(:subscription_store).new()
  defp deliveries, do: adapter(:delivery_store).new()

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
  # drift from what `Adapters.WebPushSender` actually signs with.
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
  # pre-hashed correctly.
  defp digest_session(session_key) when is_binary(session_key),
    do: :crypto.hash(:sha256, session_key) |> Base.encode16(case: :lower)
end
