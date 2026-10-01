defmodule BnestApp.Test.Contracts.DeliveryStoreContract do
  @moduledoc """
  The behaviour every `BnestApp.PushNotifications.Ports.DeliveryStore` implementation
  shares. A test module uses this template and defines:

    * `new_store/1`, which takes the ExUnit context and returns a handle over a fresh store
      with no delivery;
    * `put_delivery/2`, which takes the handle and a message body and makes one pending
      delivery the way that store's deliveries come to exist: a synthetic `test-user-`
      member displayed as "Test User" commits the body in the canonical room while exactly
      one other member's subscription is active. It returns `%{message_id:,
      subscription_id:}`.

  Every other change goes through the port, at fixed instants after the deliveries were
  committed; nothing is ever sent.
  """

  use ExUnit.CaseTemplate

  alias BnestApp.PushNotifications.Ports.DeliveryStore

  @t0 ~U[2026-09-18 00:00:00Z]

  @doc "The contract's first instant, `seconds` later."
  @spec at(integer()) :: DateTime.t()
  def at(seconds \\ 0), do: DateTime.add(@t0, seconds, :second)

  @doc "Claims the due delivery with the lowest ID at `at(seconds)`, leased for two minutes."
  @spec claim(DeliveryStore.handle(), integer()) :: DeliveryStore.claim() | nil
  def claim(store, seconds \\ 0),
    do: DeliveryStore.claim_due(store, at(seconds), at(seconds + 120))

  @doc "Makes the claimed delivery final at `at(seconds)`."
  @spec finalize!(DeliveryStore.handle(), DeliveryStore.claim(), String.t(), integer()) :: :ok
  def finalize!(store, claim, state, seconds \\ 0) do
    accepted_at = if state == "delivered", do: at(seconds)
    category = if state == "terminal", do: "provider"
    DeliveryStore.finalize!(store, claim.id, state, category, accepted_at, at(seconds))
  end

  using do
    quote do
      import BnestApp.Test.Contracts.DeliveryStoreContract, only: :functions

      alias BnestApp.PushNotifications.Ports.DeliveryStore

      setup context, do: [store: new_store(context)]

      describe "DeliveryStore contract" do
        test "claims the due delivery with the lowest ID and counts the attempt",
             %{store: store} do
          first = put_delivery(store, "first")
          second = put_delivery(store, "second")

          assert %{id: first_id, attempt: 1, created_at: %DateTime{microsecond: {0, _}}} =
                   claimed = claim(store)

          assert Map.take(claimed, [:message_id, :subscription_id]) == first
          assert %{id: second_id, attempt: 1} = claimed_second = claim(store)
          assert Map.take(claimed_second, [:message_id, :subscription_id]) == second
          assert second_id > first_id
          assert claim(store) == nil
        end

        test "a claim whose lease expired is due again", %{store: store} do
          put_delivery(store, "leased")
          %{id: id} = claim(store)

          assert claim(store, 119) == nil
          assert %{id: ^id, attempt: 2} = claim(store, 120)
        end

        test "a retryable delivery is due at its next attempt time", %{store: store} do
          put_delivery(store, "retried")
          %{id: id} = claim(store)

          assert DeliveryStore.retry!(store, id, at(30), at()) == :ok
          assert claim(store, 29) == nil
          assert %{id: ^id, attempt: 2} = claim(store, 30)
        end

        test "a final delivery is never due again", %{store: store} do
          put_delivery(store, "delivered")
          put_delivery(store, "refused")

          :ok = finalize!(store, claim(store), "delivered")
          :ok = finalize!(store, claim(store), "terminal")

          assert claim(store, 86_400 * 365) == nil
          assert DeliveryStore.count_active_unfinished(store) == 0
        end

        test "counts the deliveries neither final nor soft-deleted", %{store: store} do
          for body <- ~w(final retryable claimed pending), do: put_delivery(store, body)
          :ok = finalize!(store, claim(store), "delivered")
          :ok = DeliveryStore.retry!(store, claim(store).id, at(600), at())
          %{} = claim(store)

          assert DeliveryStore.count_active_unfinished(store) == 3
        end

        test "returns what a delivery of the message sends", %{store: store} do
          %{message_id: message_id} = put_delivery(store, "Dinner is ready")

          assert DeliveryStore.message(store, message_id) == %{
                   id: message_id,
                   body: "Dinner is ready",
                   sender_display_name: "Test User",
                   room_slug: "ruang-keluarga"
                 }

          assert DeliveryStore.message(store, message_id + 1000) == nil
        end

        test "soft-deletes final deliveries stamped by the cutoff, a batch at a time",
             %{store: store} do
          for body <- ~w(one two three later pending), do: put_delivery(store, body)
          :ok = finalize!(store, claim(store), "delivered")
          :ok = finalize!(store, claim(store), "terminal")
          :ok = finalize!(store, claim(store), "delivered")
          :ok = finalize!(store, claim(store), "delivered", 3_600)

          assert DeliveryStore.soft_delete_final!(store, at(), at(7_200), 2) == 2
          assert DeliveryStore.soft_delete_final!(store, at(), at(7_200), 2) == 1
          assert DeliveryStore.soft_delete_final!(store, at(), at(7_200), 2) == 0
          assert DeliveryStore.count_active_unfinished(store) == 1
          assert DeliveryStore.soft_delete_final!(store, at(3_600), at(7_200), 2) == 1
        end

        test "purges deliveries soft-deleted by the cutoff, a batch at a time", %{store: store} do
          for body <- ~w(one two three), do: put_delivery(store, body)
          for _final <- 1..3, do: :ok = finalize!(store, claim(store), "terminal")
          3 = DeliveryStore.soft_delete_final!(store, at(), at(7_200), 250)

          assert DeliveryStore.purge_deleted!(store, at(7_199), 2) == 0
          assert DeliveryStore.purge_deleted!(store, at(7_200), 2) == 2
          assert DeliveryStore.purge_deleted!(store, at(7_200), 2) == 1
          assert DeliveryStore.purge_deleted!(store, at(7_200), 2) == 0
          assert DeliveryStore.soft_delete_final!(store, at(), at(7_200), 250) == 0
        end

        test "a transaction returns its function's value and keeps its changes",
             %{store: store} do
          put_delivery(store, "in a transaction")

          assert DeliveryStore.transaction(store, fn ->
                   :ok = finalize!(store, claim(store), "delivered")
                   :finalized
                 end) == :finalized

          assert DeliveryStore.count_active_unfinished(store) == 0
        end
      end
    end
  end
end
