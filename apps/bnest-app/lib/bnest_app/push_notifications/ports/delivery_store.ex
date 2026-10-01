defmodule BnestApp.PushNotifications.Ports.DeliveryStore do
  @moduledoc """
  The store of family chat push deliveries: one per message and subscription it is owed
  to. Family Chat's room store records each delivery, pending and never attempted, in the
  same commit as its message; this port moves it through its attempts, retires it and
  purges it.

  Every callback except `new/0` takes the store's handle first. The handle is a map whose
  `:adapter` key names the implementing module.

  Semantics every implementation keeps:

    * A delivery is pending, claimed, retryable, delivered or terminal. Delivered and
      terminal are final. A soft-deleted delivery is never due and never counted.
    * `claim_due/3` atomically takes the due delivery with the lowest ID and returns it
      claimed as `%{id:, message_id:, subscription_id:, attempt:, created_at:}`, or nil. A
      delivery is due when it is pending or retryable with no next attempt time or one at
      or before `now`, or claimed with a lease that expired at or before `now`. Claiming
      counts one more attempt (`attempt` is the new count), holds the lease until
      `lease_until`, clears the next attempt time and stamps `now`.
    * `retry!/4` makes a delivery retryable at `next_attempt_at` with the failure category
      `"retryable"`, releasing its lease and stamping `now`.
    * `finalize!/6` gives a delivery a final state, its failure category and the time the
      provider accepted it, releasing its lease, clearing its next attempt time and
      stamping `now`.
    * `message/2` returns what a delivery of the message sends: `%{id:, body:,
      sender_display_name:, room_slug:}`, or nil.
    * `soft_delete_final!/4` soft-deletes, as the retention job, up to `limit` final
      deliveries last stamped at or before `cutoff`, lowest IDs first, and returns how
      many. `purge_deleted!/3` removes up to `limit` deliveries soft-deleted at or before
      `cutoff`, lowest IDs first, and returns how many.
    * `count_active_unfinished/1` counts the deliveries neither final nor soft-deleted.
    * `transaction/2` runs the function so that its changes to the store commit together,
      and returns the function's value.

  Every time is a UTC `DateTime`; stores keep it to the second.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}
  @type claim :: %{
          id: pos_integer(),
          message_id: pos_integer(),
          subscription_id: pos_integer(),
          attempt: pos_integer(),
          created_at: DateTime.t()
        }
  @type message :: %{
          id: pos_integer(),
          body: String.t(),
          sender_display_name: String.t(),
          room_slug: String.t()
        }

  @doc "A handle over the deliveries the running application serves."
  @callback new() :: handle()

  @callback claim_due(handle(), now :: DateTime.t(), lease_until :: DateTime.t()) :: claim() | nil

  @callback retry!(
              handle(),
              delivery_id :: pos_integer(),
              next_attempt_at :: DateTime.t(),
              now :: DateTime.t()
            ) :: :ok

  @callback finalize!(
              handle(),
              delivery_id :: pos_integer(),
              state :: String.t(),
              failure_category :: String.t() | nil,
              provider_accepted_at :: DateTime.t() | nil,
              now :: DateTime.t()
            ) :: :ok

  @callback message(handle(), message_id :: pos_integer()) :: message() | nil

  @callback soft_delete_final!(
              handle(),
              cutoff :: DateTime.t(),
              now :: DateTime.t(),
              limit :: pos_integer()
            ) :: non_neg_integer()

  @callback purge_deleted!(handle(), cutoff :: DateTime.t(), limit :: pos_integer()) ::
              non_neg_integer()

  @callback count_active_unfinished(handle()) :: non_neg_integer()

  @callback transaction(handle(), (-> result)) :: result when result: term()

  @spec claim_due(handle(), DateTime.t(), DateTime.t()) :: claim() | nil
  def claim_due(store, now, lease_until), do: store.adapter.claim_due(store, now, lease_until)

  @spec retry!(handle(), pos_integer(), DateTime.t(), DateTime.t()) :: :ok
  def retry!(store, delivery_id, next_attempt_at, now),
    do: store.adapter.retry!(store, delivery_id, next_attempt_at, now)

  @spec finalize!(
          handle(),
          pos_integer(),
          String.t(),
          String.t() | nil,
          DateTime.t() | nil,
          DateTime.t()
        ) :: :ok
  def finalize!(store, delivery_id, state, failure_category, provider_accepted_at, now) do
    store.adapter.finalize!(
      store,
      delivery_id,
      state,
      failure_category,
      provider_accepted_at,
      now
    )
  end

  @spec message(handle(), pos_integer()) :: message() | nil
  def message(store, message_id), do: store.adapter.message(store, message_id)

  @spec soft_delete_final!(handle(), DateTime.t(), DateTime.t(), pos_integer()) ::
          non_neg_integer()
  def soft_delete_final!(store, cutoff, now, limit),
    do: store.adapter.soft_delete_final!(store, cutoff, now, limit)

  @spec purge_deleted!(handle(), DateTime.t(), pos_integer()) :: non_neg_integer()
  def purge_deleted!(store, cutoff, limit), do: store.adapter.purge_deleted!(store, cutoff, limit)

  @spec count_active_unfinished(handle()) :: non_neg_integer()
  def count_active_unfinished(store), do: store.adapter.count_active_unfinished(store)

  @spec transaction(handle(), (-> result)) :: result when result: term()
  def transaction(store, fun), do: store.adapter.transaction(store, fun)
end
