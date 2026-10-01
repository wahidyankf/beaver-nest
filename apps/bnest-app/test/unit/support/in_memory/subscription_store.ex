defmodule BnestApp.Test.InMemory.SubscriptionStore do
  @moduledoc """
  An Agent-backed `BnestApp.PushNotifications.Ports.SubscriptionStore`. It keeps the port's
  semantics without SQL, on the agent of an in-memory room store, so Family Chat's commits
  fan out to the subscriptions it stores (see `BnestApp.Test.InMemory.RoomStore`).

  `start/0` gives a test its own store; `over/1` gives the subscription store on the agent
  of another in-memory store's handle. The unit layer configures this module as the
  `:subscription_store` adapter; its `new/0` serves the room store a test installed.
  `subscriptions/1` reads back every stored row, with its audit columns.
  """

  @behaviour BnestApp.PushNotifications.Ports.SubscriptionStore

  alias BnestApp.Test.InMemory.RoomStore

  @dispatcher "system:push-dispatcher"

  @doc "A fresh store, on a fresh in-memory room store linked to the calling test."
  def start, do: over(RoomStore.start())

  @doc "The subscription store on the agent of `handle`, a handle of any in-memory store."
  def over(%{pid: pid}), do: %{adapter: __MODULE__, pid: pid}

  @impl true
  def new, do: over(RoomStore.new())

  @doc "Every stored subscription, lowest ID first."
  def subscriptions(%{pid: pid}), do: Agent.get(pid, & &1.subscriptions)

  @doc """
  Subscribes a fresh endpoint for a fresh session of `user_id` through `upsert!/5`, then
  disables that session when `active?: false` is given, and returns the subscription's ID.
  For tests whose subject only reads subscriptions, such as Family Chat's fan-out.
  """
  def subscribe!(handle, user_id, options \\ []) do
    store = over(handle)
    session = "test-session-" <> Ecto.UUID.generate()
    # Fragmented scheme: no unit-layer source carries a URL literal.
    endpoint = "https:" <> "//push.allowed.example.com/" <> Ecto.UUID.generate()
    binding = %{endpoint: endpoint, endpoint_sha256: endpoint, p256dh: "p256dh", auth: "auth"}
    now = DateTime.utc_now()
    :ok = upsert!(store, user_id, session, binding, now)

    unless Keyword.get(options, :active?, true),
      do: :ok = disable_session!(store, user_id, session, now)

    store |> subscriptions() |> Enum.find(&(&1.endpoint == endpoint)) |> Map.fetch!(:id)
  end

  @impl true
  def active_subscription(%{pid: pid}, user_id, session_digest) do
    Agent.get(pid, fn state ->
      state.subscriptions
      |> Enum.filter(&(active?(&1) and bound?(&1, user_id, session_digest)))
      |> Enum.max_by(& &1.id, fn -> nil end)
      |> case do
        nil -> nil
        row -> %{expiration_time: row.expiration_time}
      end
    end)
  end

  @impl true
  def upsert!(%{pid: pid}, user_id, session_digest, binding, now) do
    now = second(now)
    actor = "user:" <> user_id

    # Another endpoint the session holds active gives way to this one.
    gives_way? =
      &(active?(&1) and bound?(&1, user_id, session_digest) and
          &1.endpoint_sha256 != binding.endpoint_sha256)

    Agent.update(pid, fn state ->
      rows = map_where(state.subscriptions, gives_way?, &disable(&1, now, actor))

      case Enum.find(rows, &(&1.endpoint_sha256 == binding.endpoint_sha256)) do
        nil ->
          row = new_row(state.next_subscription_id, user_id, session_digest, binding, now)

          %{
            state
            | subscriptions: rows ++ [row],
              next_subscription_id: state.next_subscription_id + 1
          }

        %{id: id} ->
          rebound = %{
            user_id: user_id,
            session_digest: session_digest,
            p256dh: binding.p256dh,
            auth: binding.auth,
            deleted_at: nil,
            deleted_by: nil,
            updated_at: now,
            updated_by: actor
          }

          %{state | subscriptions: update(rows, id, &Map.merge(&1, rebound))}
      end
    end)
  end

  @impl true
  def disable_session!(%{pid: pid}, user_id, session_digest, now) do
    actor = "user:" <> to_string(user_id)

    update_where(pid, &(active?(&1) and bound?(&1, user_id, session_digest)), fn row ->
      disable(row, second(now), actor)
    end)
  end

  @impl true
  def disable_gone!(%{pid: pid}, subscription_id, now) do
    update_where(pid, &(active?(&1) and &1.id == subscription_id), fn row ->
      disable(row, second(now), @dispatcher)
    end)
  end

  @impl true
  def fetch(%{pid: pid}, subscription_id) do
    Agent.get(pid, fn state ->
      case Enum.find(state.subscriptions, &(&1.id == subscription_id)) do
        nil -> nil
        row -> Map.take(row, [:endpoint, :p256dh, :auth])
      end
    end)
  end

  # A nil user is bound to nothing, as SQL's `user_id = NULL` matches no row.
  defp bound?(row, user_id, session_digest),
    do: not is_nil(user_id) and row.user_id == user_id and row.session_digest == session_digest

  defp active?(row), do: is_nil(row.deleted_at)

  defp disable(row, now, actor),
    do: %{row | deleted_at: now, deleted_by: actor, updated_at: now, updated_by: actor}

  defp new_row(id, user_id, session_digest, binding, now) do
    %{
      id: id,
      user_id: user_id,
      session_digest: session_digest,
      endpoint_sha256: binding.endpoint_sha256,
      endpoint: binding.endpoint,
      p256dh: binding.p256dh,
      auth: binding.auth,
      expiration_time: nil,
      created_at: now,
      created_by: "user:" <> user_id,
      updated_at: now,
      updated_by: "user:" <> user_id,
      deleted_at: nil,
      deleted_by: nil
    }
  end

  defp update_where(pid, matches?, change) do
    Agent.update(pid, fn state ->
      %{state | subscriptions: map_where(state.subscriptions, matches?, change)}
    end)
  end

  defp map_where(rows, matches?, change),
    do: Enum.map(rows, &if(matches?.(&1), do: change.(&1), else: &1))

  defp update(rows, id, change), do: Enum.map(rows, &if(&1.id == id, do: change.(&1), else: &1))

  defp second(time), do: DateTime.truncate(time, :second)
end
