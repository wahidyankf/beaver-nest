defmodule BnestApp.Test.Contracts.RoomStoreContract do
  @moduledoc """
  The behaviour every `BnestApp.FamilyChat.Ports.RoomStore` implementation shares. A test
  module uses this template and defines `new_store/1`, which takes the ExUnit context and
  returns a handle over a fresh store with no message and no push subscription; the
  template then runs the whole contract against it through the port.

  The store only reads push subscriptions, which PushNotifications owns, so the test module
  also defines `put_subscription/2`: given the handle and `user_id:` (plus `active?: false`
  for a subscription its owner disabled), it stores one subscription the way that adapter's
  subscriptions come to exist and returns its ID. The delivery cases below pin each
  commit's fan-out against those subscriptions.

  Messages are sent by synthetic `test-user-` identities into the canonical room, the only
  room a store seeds.
  """

  use ExUnit.CaseTemplate

  alias BnestApp.FamilyChat.Ports.RoomStore

  @room_id 1
  @sender "test-user-contract-sender"
  @message_keys ~w(body committed_at id idempotency_key reply_to_message_id room_id sender_display_name sender_id sender_kind)a

  @doc "Commits `body` from the synthetic user `sender` under `key`, replying to `reply_to`."
  @spec commit!(RoomStore.handle(), String.t(), String.t(), pos_integer() | nil, String.t()) ::
          {:ok, RoomStore.message()}
  def commit!(store, key, body, reply_to \\ nil, sender \\ @sender),
    do:
      RoomStore.insert_message!(store, @room_id, "user", sender, "Test User", key, body, reply_to)

  @doc "Commits `body` as a system message whose sender ID is the default user's."
  @spec system_commit!(RoomStore.handle(), String.t(), String.t()) :: {:ok, RoomStore.message()}
  def system_commit!(store, key, body),
    do: RoomStore.insert_message!(store, @room_id, "system", @sender, "System", key, body, nil)

  @doc "The user message `sender` committed under `key`, or nil."
  @spec find(RoomStore.handle(), String.t(), String.t()) :: RoomStore.message() | nil
  def find(store, key, sender \\ @sender),
    do: RoomStore.find_message(store, @room_id, "user", sender, key)

  @doc "The message IDs of a page and its two flags."
  @spec page(RoomStore.handle(), pos_integer() | nil, pos_integer() | nil, pos_integer()) ::
          {[pos_integer()], boolean(), boolean()}
  def page(store, before_id, after_id, limit) do
    %{nodes: nodes, has_older: has_older, has_newer: has_newer} =
      RoomStore.list_messages(store, @room_id, before_id, after_id, limit)

    {Enum.map(nodes, & &1.id), has_older, has_newer}
  end

  @doc "The message as a read returns it: the committed message without its deliveries."
  @spec stored(RoomStore.message()) :: RoomStore.message()
  def stored(message), do: Map.delete(message, :deliveries)

  @doc "The keys every stored message carries."
  @spec message_keys() :: [atom()]
  def message_keys, do: @message_keys

  @doc """
  The subscription IDs a commit owes a delivery, ascending. Every delivery a commit returns
  is pending and names only its subscription; anything else fails the match.
  """
  @spec owed(RoomStore.message()) :: [pos_integer()]
  def owed(%{deliveries: deliveries}) do
    deliveries
    |> Enum.map(fn %{state: "pending", subscription_id: id} = delivery
                   when map_size(delivery) == 2 ->
      id
    end)
    |> Enum.sort()
  end

  using do
    quote do
      import BnestApp.Test.Contracts.RoomStoreContract, only: :functions

      alias BnestApp.FamilyChat.Ports.RoomStore
      alias BnestApp.Test.Contracts.RoomStoreContract

      require RoomStoreContract

      setup context, do: [store: new_store(context)]

      describe "RoomStore contract" do
        test "seeds the canonical room once", %{store: store} do
          assert RoomStore.ensure_ready!(store) == :ok
          assert RoomStore.ensure_ready!(store) == :ok

          assert [room] = RoomStore.list_active_rooms(store)

          assert %{
                   id: 1,
                   slug: "ruang-keluarga",
                   name: "Ruang Keluarga",
                   room_kind: "conversation",
                   member_posting_enabled: true,
                   created_by: "system:migration",
                   updated_by: "system:migration"
                 } = room

          assert %DateTime{} = room.created_at
          assert RoomStore.get_active_room(store, "ruang-keluarga") == room
          assert RoomStore.get_active_room(store, "no-such-room") == nil
        end

        test "commits a message with every stored field and no delivery to owe",
             %{store: store} do
          {:ok, message} = commit!(store, "key-fields", "Dinner is ready")

          assert message.deliveries == []
          assert message |> stored() |> Map.keys() |> Enum.sort() == message_keys()

          assert %{
                   room_id: 1,
                   sender_kind: "user",
                   sender_id: "test-user-contract-sender",
                   sender_display_name: "Test User",
                   idempotency_key: "key-fields",
                   body: "Dinner is ready",
                   reply_to_message_id: nil
                 } = message

          assert is_integer(message.id) and message.id > 0
          assert %DateTime{microsecond: {0, _precision}} = message.committed_at
        end

        test "an idempotency key commits one message per sender", %{store: store} do
          {:ok, first} = commit!(store, "key-once", "first body")
          assert find(store, "key-once") == stored(first)
          assert catch_error(commit!(store, "key-once", "a different body"))
          assert find(store, "key-once") == stored(first)

          {:ok, other_sender} =
            commit!(store, "key-once", "other sender", nil, "test-user-contract-b")

          {:ok, system} = system_commit!(store, "key-once", "system sender")

          assert Enum.uniq([first.id, other_sender.id, system.id]) ==
                   [first.id, other_sender.id, system.id]

          assert find(store, "no-key") == nil

          assert {Enum.sort([first.id, other_sender.id, system.id]), false, false} ==
                   page(store, nil, nil, 50)
        end

        test "IDs ascend in commit order and a page reads them ascending", %{store: store} do
          messages =
            for n <- 1..3 do
              {:ok, message} = commit!(store, "key-order-#{n}", "message #{n}")
              message
            end

          ids = Enum.map(messages, & &1.id)
          assert ids == Enum.sort(ids) and ids == Enum.uniq(ids)

          %{nodes: nodes} = RoomStore.list_messages(store, 1, nil, nil, 50)
          assert nodes == Enum.map(messages, &stored/1)
        end

        test "pages by cursor in either direction", %{store: store} do
          [a, b, c, d, e] =
            for n <- 1..5 do
              {:ok, message} = commit!(store, "key-page-#{n}", "page #{n}")
              message.id
            end

          assert page(store, nil, nil, 2) == {[d, e], true, false}
          assert page(store, nil, nil, 5) == {[a, b, c, d, e], false, false}
          assert page(store, d, nil, 2) == {[b, c], true, true}
          assert page(store, b, nil, 2) == {[a], false, true}
          assert page(store, a, nil, 2) == {[], false, true}
          assert page(store, nil, a, 2) == {[b, c], false, true}
          assert page(store, nil, b, 2) == {[c, d], true, true}
          assert page(store, nil, d, 2) == {[e], true, false}
          assert page(store, nil, e, 2) == {[], true, false}
        end

        test "a reply links to its target in the same room", %{store: store} do
          {:ok, target} = commit!(store, "key-target", "Nanti aku jemput jam 5")
          {:ok, reply} = commit!(store, "key-reply", "Oke, aku siapin", target.id)

          assert target.reply_to_message_id == nil
          assert reply.reply_to_message_id == target.id
          assert RoomStore.message_by_id(store, 1, reply.id) == stored(reply)
          assert RoomStore.message_by_id(store, 1, target.id) == stored(target)
          assert RoomStore.message_by_id(store, 2, target.id) == nil

          assert RoomStore.quotes_for(store, 1, [reply, stored(target), reply]) ==
                   %{target.id => stored(target)}

          assert RoomStore.quotes_for(store, 1, []) == %{}
          assert RoomStore.quotes_for(store, 1, [%{reply_to_message_id: nil}]) == %{}
          assert RoomStore.quotes_for(store, 1, [%{reply_to_message_id: reply.id + 1000}]) == %{}
          assert RoomStore.quotes_for(store, 2, [reply]) == %{}
        end

        test "a reply to no message is refused and commits nothing", %{store: store} do
          {:ok, target} = commit!(store, "key-real-target", "a real target")

          assert catch_error(commit!(store, "key-dangling", "answers nothing", target.id + 1000))

          assert find(store, "key-dangling") == nil
          assert page(store, nil, nil, 50) == {[target.id], false, false}
        end

        test "committed messages stay as first committed", %{store: store} do
          {:ok, first} = commit!(store, "key-append-1", "the first message")
          before = RoomStore.message_by_id(store, 1, first.id)

          {:ok, _reply} = commit!(store, "key-append-2", "an answer", first.id)
          assert catch_error(commit!(store, "key-append-1", "a rewrite attempt"))
          :ok = RoomStore.ensure_ready!(store)

          assert RoomStore.message_by_id(store, 1, first.id) == before
          assert before == stored(first)
          %{nodes: [oldest | _rest]} = RoomStore.list_messages(store, 1, nil, nil, 50)
          assert oldest == before
        end
      end

      RoomStoreContract.delivery_cases()
    end
  end

  @doc """
  The cases pinning each commit's push-delivery fan-out, injected by `using/1` (kept apart
  so neither quote grows past a readable length). They rely on the caller's
  `put_subscription/2` and the `store` from the template's setup.
  """
  defmacro delivery_cases do
    quote do
      describe "RoomStore delivery contract" do
        test "a commit owes one pending delivery to each other active subscription",
             %{store: store} do
          own = put_subscription(store, user_id: "test-user-contract-sender")
          phone = put_subscription(store, user_id: "test-user-contract-other")
          tablet = put_subscription(store, user_id: "test-user-contract-other")
          third = put_subscription(store, user_id: "test-user-contract-third")

          {:ok, message} = commit!(store, "key-fan-out", "Dinner is ready")

          assert owed(message) == Enum.sort([phone, tablet, third])
          refute own in owed(message)
        end

        test "a system message owes a delivery to every active subscription", %{store: store} do
          own = put_subscription(store, user_id: "test-user-contract-sender")
          other = put_subscription(store, user_id: "test-user-contract-other")

          {:ok, message} = system_commit!(store, "key-system-fan-out", "Pemberitahuan")

          assert owed(message) == Enum.sort([own, other])
        end

        test "an inactive subscription is owed nothing", %{store: store} do
          active = put_subscription(store, user_id: "test-user-contract-other")
          put_subscription(store, user_id: "test-user-contract-retired", active?: false)

          {:ok, from_user} = commit!(store, "key-inactive", "hello")
          {:ok, from_system} = system_commit!(store, "key-inactive-system", "notice")

          assert owed(from_user) == [active]
          assert owed(from_system) == [active]
        end

        test "a reply owes exactly the deliveries an ordinary message does", %{store: store} do
          own = put_subscription(store, user_id: "test-user-contract-sender")
          other = put_subscription(store, user_id: "test-user-contract-other")
          third = put_subscription(store, user_id: "test-user-contract-third")

          {:ok, target} =
            commit!(
              store,
              "key-quoted",
              "Nanti aku jemput jam 5",
              nil,
              "test-user-contract-other"
            )

          {:ok, ordinary} = commit!(store, "key-ordinary", "Oke")
          {:ok, reply} = commit!(store, "key-answer", "Oke, aku siapin", target.id)

          assert owed(target) == Enum.sort([own, third])
          assert owed(ordinary) == Enum.sort([other, third])
          assert owed(reply) == owed(ordinary)
        end
      end
    end
  end
end
