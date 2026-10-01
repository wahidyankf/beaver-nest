defmodule BnestApp.PushNotifications.Ports.SubscriptionStore do
  @moduledoc """
  The store of Web Push subscriptions. Each subscription binds one browser endpoint to the
  user and session that enabled it, with the endpoint's encryption keys.

  Every callback except `new/0` takes the store's handle first. The handle is a map whose
  `:adapter` key names the implementing module, so the application dispatches through the
  functions below without knowing which store is active.

  Semantics every implementation keeps:

    * An endpoint is stored at most once, identified by its digest. A subscription is
      active until it is disabled; a disabled one keeps its ID, endpoint and keys.
    * `upsert!/5` binds the endpoint in `binding` to the user and session, as one atomic
      change: it first disables every other active subscription of that user and session
      whose endpoint differs, then reactivates the subscription already stored for the
      endpoint, active or not, rebinding it to the user, session and keys given, or else
      stores a new active one. The user's ID is the audit actor.
    * `active_subscription/3` returns the newest active subscription of the user and
      session as `%{expiration_time: _}`, or nil. A nil user has none.
    * `disable_session!/4` disables the user's active subscriptions of the session, with
      the user as the audit actor; `disable_gone!/3` disables the subscription with the
      ID, on the dispatcher's behalf. Disabling an inactive subscription changes nothing.
    * `fetch/2` returns the endpoint and keys (`:endpoint`, `:p256dh`, `:auth`) of the
      subscription with the ID, active or not, or nil.

  Every time is a UTC `DateTime`; stores keep it to the second.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}
  @type binding :: %{
          endpoint: String.t(),
          endpoint_sha256: String.t(),
          p256dh: String.t(),
          auth: String.t()
        }
  @type keys :: %{endpoint: String.t(), p256dh: String.t(), auth: String.t()}

  @doc "A handle over the subscriptions the running application serves."
  @callback new() :: handle()

  @callback active_subscription(
              handle(),
              user_id :: String.t() | nil,
              session_digest :: String.t()
            ) ::
              %{expiration_time: term()} | nil

  @callback upsert!(
              handle(),
              user_id :: String.t(),
              session_digest :: String.t(),
              binding(),
              now :: DateTime.t()
            ) :: :ok

  @callback disable_session!(
              handle(),
              user_id :: String.t() | nil,
              session_digest :: String.t(),
              now :: DateTime.t()
            ) :: :ok

  @callback disable_gone!(handle(), subscription_id :: pos_integer(), now :: DateTime.t()) :: :ok

  @callback fetch(handle(), subscription_id :: pos_integer()) :: keys() | nil

  @spec active_subscription(handle(), String.t() | nil, String.t()) ::
          %{expiration_time: term()} | nil
  def active_subscription(store, user_id, session_digest),
    do: store.adapter.active_subscription(store, user_id, session_digest)

  @spec upsert!(handle(), String.t(), String.t(), binding(), DateTime.t()) :: :ok
  def upsert!(store, user_id, session_digest, binding, now),
    do: store.adapter.upsert!(store, user_id, session_digest, binding, now)

  @spec disable_session!(handle(), String.t() | nil, String.t(), DateTime.t()) :: :ok
  def disable_session!(store, user_id, session_digest, now),
    do: store.adapter.disable_session!(store, user_id, session_digest, now)

  @spec disable_gone!(handle(), pos_integer(), DateTime.t()) :: :ok
  def disable_gone!(store, subscription_id, now),
    do: store.adapter.disable_gone!(store, subscription_id, now)

  @spec fetch(handle(), pos_integer()) :: keys() | nil
  def fetch(store, subscription_id), do: store.adapter.fetch(store, subscription_id)
end
