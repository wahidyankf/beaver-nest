defmodule BnestApp.Test.Contracts.SubscriptionStoreContract do
  @moduledoc """
  The behaviour every `BnestApp.PushNotifications.Ports.SubscriptionStore` implementation
  shares. A test module uses this template and defines:

    * `new_store/1`, which takes the ExUnit context and returns a handle over a fresh store
      with no subscription;
    * `stored/2`, which takes the handle and an endpoint and returns how the store holds
      that endpoint's subscription, `%{id:, user_id:, session_digest:, active?:}`, or nil.
      The port answers only by user and session, so the template reads IDs and bindings
      through it.

  Subscriptions belong to synthetic `test-user-` identities, on endpoints of the synthetic
  provider host; nothing is ever sent.
  """

  use ExUnit.CaseTemplate

  alias BnestApp.PushNotifications.Ports.SubscriptionStore

  @now ~U[2026-09-18 00:00:00Z]

  @doc "A fixed instant the contract stamps its changes with."
  @spec now() :: DateTime.t()
  def now, do: @now

  @doc """
  A binding of a fresh endpoint named by `suffix`, with fresh keys. The scheme is built
  from fragments so no unit-layer source carries a URL literal.
  """
  @spec binding_for(String.t()) :: SubscriptionStore.binding()
  def binding_for(suffix) do
    endpoint = "https:" <> "//push.allowed.example.com/contract/" <> suffix
    rebind(%{endpoint: endpoint, endpoint_sha256: digest(endpoint)})
  end

  @doc "The same endpoint with fresh keys, as a browser that subscribed again sends it."
  @spec rebind(map()) :: SubscriptionStore.binding()
  def rebind(%{endpoint: endpoint, endpoint_sha256: endpoint_sha256}) do
    %{
      endpoint: endpoint,
      endpoint_sha256: endpoint_sha256,
      p256dh: key(65),
      auth: key(16)
    }
  end

  @doc "Binds `binding` to the user and session at the contract's instant."
  @spec upsert!(SubscriptionStore.handle(), String.t(), String.t(), SubscriptionStore.binding()) ::
          :ok
  def upsert!(store, user_id, session, binding),
    do: SubscriptionStore.upsert!(store, user_id, session, binding, @now)

  defp digest(endpoint), do: :crypto.hash(:sha256, endpoint) |> Base.encode16(case: :lower)

  defp key(bytes),
    do: :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false)

  using do
    quote do
      import BnestApp.Test.Contracts.SubscriptionStoreContract, only: :functions

      alias BnestApp.PushNotifications.Ports.SubscriptionStore

      # Session digests shaped as the facade stores them: 64 lowercase hex characters.
      @session_a String.duplicate("a", 64)
      @session_b String.duplicate("b", 64)

      setup context, do: [store: new_store(context)]

      describe "SubscriptionStore contract" do
        test "an upsert makes the subscription its session's active one", %{store: store} do
          binding = binding_for("first")
          assert upsert!(store, "test-user-contract-a", @session_a, binding) == :ok

          assert SubscriptionStore.active_subscription(store, "test-user-contract-a", @session_a) ==
                   %{expiration_time: nil}

          assert SubscriptionStore.active_subscription(store, "test-user-contract-a", @session_b) ==
                   nil

          assert SubscriptionStore.active_subscription(store, "test-user-contract-b", @session_a) ==
                   nil

          assert SubscriptionStore.active_subscription(store, nil, @session_a) == nil

          assert %{user_id: "test-user-contract-a", session_digest: @session_a, active?: true} =
                   stored(store, binding.endpoint)

          assert %{endpoint: binding.endpoint, p256dh: binding.p256dh, auth: binding.auth} ==
                   SubscriptionStore.fetch(store, stored(store, binding.endpoint).id)
        end

        test "upserting the same endpoint again keeps one active subscription", %{store: store} do
          binding = binding_for("same")
          :ok = upsert!(store, "test-user-contract-a", @session_a, binding)
          %{id: id} = stored(store, binding.endpoint)

          :ok = upsert!(store, "test-user-contract-a", @session_a, binding)

          assert %{id: ^id, active?: true} = stored(store, binding.endpoint)
        end

        test "a session that subscribes a new endpoint disables its old one", %{store: store} do
          old = binding_for("old-device-key")
          new = binding_for("new-device-key")
          other_session = binding_for("other-session")
          :ok = upsert!(store, "test-user-contract-a", @session_a, old)
          :ok = upsert!(store, "test-user-contract-a", @session_b, other_session)

          :ok = upsert!(store, "test-user-contract-a", @session_a, new)

          assert %{active?: false} = stored(store, old.endpoint)
          assert %{active?: true, session_digest: @session_a} = stored(store, new.endpoint)
          assert %{active?: true} = stored(store, other_session.endpoint)

          assert SubscriptionStore.active_subscription(store, "test-user-contract-a", @session_a) ==
                   %{expiration_time: nil}
        end

        test "an endpoint another session subscribes is rebound, not duplicated", %{store: store} do
          binding = binding_for("shared")
          :ok = upsert!(store, "test-user-contract-a", @session_a, binding)
          %{id: id} = stored(store, binding.endpoint)
          rebound = rebind(binding)

          :ok = upsert!(store, "test-user-contract-b", @session_b, rebound)

          assert stored(store, binding.endpoint) ==
                   %{
                     id: id,
                     user_id: "test-user-contract-b",
                     session_digest: @session_b,
                     active?: true
                   }

          assert SubscriptionStore.active_subscription(store, "test-user-contract-a", @session_a) ==
                   nil

          assert SubscriptionStore.fetch(store, id) ==
                   %{endpoint: binding.endpoint, p256dh: rebound.p256dh, auth: rebound.auth}
        end

        test "disabling a session disables only its subscriptions, once", %{store: store} do
          first = binding_for("session-one")
          second = binding_for("session-two")
          :ok = upsert!(store, "test-user-contract-a", @session_a, first)
          :ok = upsert!(store, "test-user-contract-a", @session_b, second)

          for _twice <- 1..2 do
            assert SubscriptionStore.disable_session!(
                     store,
                     "test-user-contract-a",
                     @session_a,
                     now()
                   ) == :ok
          end

          assert SubscriptionStore.active_subscription(store, "test-user-contract-a", @session_a) ==
                   nil

          assert %{active?: false} = stored(store, first.endpoint)
          assert %{active?: true} = stored(store, second.endpoint)
          assert SubscriptionStore.disable_session!(store, nil, @session_b, now()) == :ok
          assert %{active?: true} = stored(store, second.endpoint)
        end

        test "a disabled subscription is reactivated by its endpoint", %{store: store} do
          binding = binding_for("comes-back")
          :ok = upsert!(store, "test-user-contract-a", @session_a, binding)
          %{id: id} = stored(store, binding.endpoint)

          :ok =
            SubscriptionStore.disable_session!(store, "test-user-contract-a", @session_a, now())

          :ok = upsert!(store, "test-user-contract-a", @session_a, binding)

          assert %{id: ^id, active?: true} = stored(store, binding.endpoint)
        end

        test "a gone subscription is disabled by its ID and still fetched", %{store: store} do
          gone = binding_for("gone")
          kept = binding_for("kept")
          :ok = upsert!(store, "test-user-contract-a", @session_a, gone)
          :ok = upsert!(store, "test-user-contract-b", @session_b, kept)
          %{id: id} = stored(store, gone.endpoint)

          assert SubscriptionStore.disable_gone!(store, id, now()) == :ok
          assert SubscriptionStore.disable_gone!(store, id, now()) == :ok

          assert %{active?: false} = stored(store, gone.endpoint)
          assert %{active?: true} = stored(store, kept.endpoint)

          assert SubscriptionStore.active_subscription(store, "test-user-contract-a", @session_a) ==
                   nil

          assert SubscriptionStore.fetch(store, id) ==
                   %{endpoint: gone.endpoint, p256dh: gone.p256dh, auth: gone.auth}

          assert SubscriptionStore.fetch(store, id + 1000) == nil
        end
      end
    end
  end
end
