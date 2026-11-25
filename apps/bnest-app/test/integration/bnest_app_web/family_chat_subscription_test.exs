defmodule BnestAppWeb.FamilyChatSubscriptionTest do
  @moduledoc """
  The `familyChatMessageCommitted` subscription at the real socket boundary.

  Each case joins Absinthe's control channel through `BnestAppWeb.UserSocket`
  with the session the HTTP pipeline wrote, subscribes its own document, and
  then drives the trigger (a commit, a rejected reply, or an `afterId` page)
  through the genuine commit and query paths. The asserted push is the channel's
  own `subscription:data`, never a driver recording.
  """
  use BnestAppWeb.ConnCase, async: false

  require Phoenix.ChannelTest

  import Phoenix.ChannelTest,
    only: [assert_reply: 4, assert_push: 3, refute_push: 2]

  alias BnestApp.FamilyChat

  @endpoint BnestAppWeb.Endpoint
  @path "/api/graphql"

  setup %{conn: conn} do
    conn = authenticated_conn(conn)
    {:ok, _room} = FamilyChat.migrate!()
    session = conn |> get("/") |> get_session()

    {:ok, socket} =
      Phoenix.ChannelTest.connect(BnestAppWeb.UserSocket, %{}, connect_info: %{session: session})

    {:ok, socket: socket}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A subscriber receives exactly one event per committed message
  test "a commit pushes one event and a duplicate retry pushes none", %{socket: socket} do
    subscribe!(
      socket,
      "subscription($roomSlug: String!) { familyChatMessageCommitted(roomSlug: $roomSlug) { id body } }"
    )

    client_message_id = Ecto.UUID.generate()
    sender = "test-user-subscription-" <> Ecto.UUID.generate()

    assert {:ok, message} =
             FamilyChat.send_message(
               sender,
               FamilyChat.canonical_room_slug(),
               client_message_id,
               "Subscribed event"
             )

    assert_push "subscription:data",
                %{result: %{data: %{"familyChatMessageCommitted" => pushed}}},
                5_000

    assert pushed["id"] == to_string(message.id)
    assert pushed["body"] == "Subscribed event"

    assert {:ok, replayed} =
             FamilyChat.send_message(
               sender,
               FamilyChat.canonical_room_slug(),
               client_message_id,
               "a different body"
             )

    assert replayed.id == message.id
    refute_push "subscription:data", _
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A rejected reply target publishes no event
  test "a reply naming a missing target is refused and pushes no event", %{socket: socket} do
    subscribe!(
      socket,
      "subscription($roomSlug: String!) { familyChatMessageCommitted(roomSlug: $roomSlug) { id body } }"
    )

    assert {:error, %{code: "VALIDATION_FAILED"}} =
             FamilyChat.send_message(
               "test-user-subscription-" <> Ecto.UUID.generate(),
               FamilyChat.canonical_room_slug(),
               Ecto.UUID.generate(),
               "answers nothing",
               "Ayah",
               _missing = 999_999_999
             )

    refute_push "subscription:data", _
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A subscriber catches up a missed event through afterId
  test "a message committed before subscribing is caught up through afterId", %{
    socket: socket,
    conn: conn
  } do
    {:ok, missed} =
      FamilyChat.send_message(
        "test-user-subscription-" <> Ecto.UUID.generate(),
        FamilyChat.canonical_room_slug(),
        Ecto.UUID.generate(),
        "missed while away"
      )

    subscribe!(
      socket,
      "subscription($roomSlug: String!) { familyChatMessageCommitted(roomSlug: $roomSlug) { id body } }"
    )

    response =
      post_graphql(
        conn,
        "query($roomSlug: String!, $afterId: ID) { familyChatMessages(roomSlug: $roomSlug, afterId: $afterId, limit: 50) { nodes { id body } } }",
        %{"roomSlug" => FamilyChat.canonical_room_slug(), "afterId" => missed.id - 1}
      )

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    refute Map.has_key?(body, "errors")

    nodes = body["data"]["familyChatMessages"]["nodes"]
    assert Enum.any?(nodes, &(&1["id"] == to_string(missed.id)))
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A subscribed reply arrives carrying its quote
  test "a reply push carries the quote it answers", %{socket: socket} do
    subscribe!(socket, """
    subscription($roomSlug: String!) {
      familyChatMessageCommitted(roomSlug: $roomSlug) {
        id
        body
        replyTo { id senderDisplayName bodyPreview }
      }
    }
    """)

    sender = "test-user-subscription-" <> Ecto.UUID.generate()

    {:ok, target} =
      FamilyChat.send_message(
        sender,
        FamilyChat.canonical_room_slug(),
        Ecto.UUID.generate(),
        "quoted question"
      )

    assert_push "subscription:data", _, 5_000

    {:ok, reply} =
      FamilyChat.send_message(
        "test-user-subscription-" <> Ecto.UUID.generate(),
        FamilyChat.canonical_room_slug(),
        Ecto.UUID.generate(),
        "reply answer",
        "Member",
        target.id
      )

    assert_push "subscription:data",
                %{result: %{data: %{"familyChatMessageCommitted" => pushed}}},
                5_000

    assert pushed["id"] == to_string(reply.id)
    assert pushed["replyTo"]["id"] == to_string(target.id)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A subscription push carries bodyHtml
  test "a push carries the message body as safe HTML", %{socket: socket} do
    subscribe!(socket, """
    subscription($roomSlug: String!) {
      familyChatMessageCommitted(roomSlug: $roomSlug) {
        id
        bodyHtml
      }
    }
    """)

    assert {:ok, _message} =
             FamilyChat.send_message(
               "test-user-subscription-" <> Ecto.UUID.generate(),
               FamilyChat.canonical_room_slug(),
               Ecto.UUID.generate(),
               "**Dinner** is ready"
             )

    assert_push "subscription:data",
                %{result: %{data: %{"familyChatMessageCommitted" => pushed}}},
                5_000

    assert pushed["bodyHtml"] =~ "<strong>Dinner</strong> is ready"
  end

  defp subscribe!(socket, query) do
    {:ok, _, socket} =
      Phoenix.ChannelTest.subscribe_and_join(socket, "__absinthe__:control", %{})

    ref =
      Phoenix.ChannelTest.push(socket, "doc", %{
        "query" => query,
        "variables" => %{"roomSlug" => FamilyChat.canonical_room_slug()}
      })

    assert_reply ref, :ok, %{subscriptionId: subscription_id}, 5_000
    assert is_binary(subscription_id)
  end

  defp post_graphql(conn, query, variables) do
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(@path, Jason.encode!(%{"query" => query, "variables" => variables}))
  end
end
