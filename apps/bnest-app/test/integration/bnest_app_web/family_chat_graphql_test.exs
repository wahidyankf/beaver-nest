defmodule BnestAppWeb.FamilyChatGraphqlTest do
  @moduledoc """
  The reply contract at the real `/api/graphql` boundary.

  Runs the genuine Plug pipeline -- endpoint, router, CSRF/session plugs, and
  `Absinthe.Plug` -- in process, which is the first of the two forms
  `repo-governance/development/api-testing.md` permits for an integration test
  ("either in-process or through a loopback listener the test starts, owns, and
  stops"). In-process keeps this suite from binding a second listener beside a
  24/7 service; the real socket layer is proved separately by `bnest-app-be-e2e`.

  Every case asserts the whole envelope the API standard names -- HTTP status,
  content type, the `data`/`errors` shape, and variable coercion -- because a
  `200` with an `errors` body is not success.
  """
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias BnestApp.FamilyChat
  alias BnestApp.FamilyChat.Adapters.SqliteRoomStore
  alias BnestApp.FamilyChat.Ports.RoomStore

  @path "/api/graphql"

  @send_reply """
  mutation SendFamilyChatReply(
    $roomSlug: String!
    $clientMessageId: ID!
    $body: String!
    $replyToMessageId: ID
  ) {
    sendFamilyChatMessage(
      roomSlug: $roomSlug
      clientMessageId: $clientMessageId
      body: $body
      replyToMessageId: $replyToMessageId
    ) {
      id
      body
      replyTo {
        id
        senderKind
        senderDisplayName
        bodyPreview
      }
    }
  }
  """

  setup %{conn: conn} do
    conn = authenticated_conn(conn)
    {:ok, _room} = FamilyChat.migrate!()
    {:ok, conn: conn}
  end

  describe "sendFamilyChatMessage with a reply target" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member sends a reply and the commit carries its quote
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A quote carries a plain text preview and no HTML
    test "commits the reply and returns its quote", %{conn: conn} do
      target = commit_target!()

      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => "Oke, aku siapin",
          # Sent as a string, as a real client sends an ID: coercion is part
          # of the contract this test is here to pin.
          "replyToMessageId" => to_string(target.id)
        })

      assert response.status == 200
      assert json_content_type?(response)

      body = Jason.decode!(response.resp_body)
      refute Map.has_key?(body, "errors")

      assert %{
               "data" => %{
                 "sendFamilyChatMessage" => %{
                   "id" => id,
                   "body" => "Oke, aku siapin",
                   "replyTo" => quoted
                 }
               }
             } = body

      assert is_binary(id)

      assert quoted == %{
               "id" => to_string(target.id),
               "senderKind" => "user",
               "senderDisplayName" => target.sender_display_name,
               "bodyPreview" => target.body
             }
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A message sent with no reply target has no quote
    test "omitting the target returns a message with a null quote", %{conn: conn} do
      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => "Dinner is ready"
        })

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      refute Map.has_key?(body, "errors")
      assert %{"data" => %{"sendFamilyChatMessage" => %{"replyTo" => nil}}} = body
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A reply target the server cannot honour is rejected before commit
    test "a target no message has is a safe validation error, and commits nothing", %{conn: conn} do
      client_message_id = Ecto.UUID.generate()

      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => client_message_id,
          "body" => "answers nothing",
          "replyToMessageId" => "999999999"
        })

      # A transport 200 carrying a GraphQL error is the contract here, which is
      # exactly why the status alone is never the assertion.
      assert response.status == 200
      assert json_content_type?(response)

      body = Jason.decode!(response.resp_body)
      assert %{"data" => %{"sendFamilyChatMessage" => nil}} = body

      assert [%{"message" => message, "extensions" => %{"code" => "VALIDATION_FAILED"}}] =
               body["errors"]

      # Safe error: no server internals, no echo of the rejected target.
      assert message == "The request is invalid."
      refute message =~ "999999999"

      assert RoomStore.find_message(
               SqliteRoomStore.new(),
               1,
               "user",
               test_user_id(),
               client_message_id
             ) == nil
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: An unauthenticated visitor is denied family chat data
    test "an unauthenticated caller is refused before any room lookup", %{conn: _conn} do
      response =
        post_graphql(build_conn(), @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => "Not allowed",
          "replyToMessageId" => "1"
        })

      assert response.status == 200
      assert json_content_type?(response)

      body = Jason.decode!(response.resp_body)
      assert %{"data" => %{"sendFamilyChatMessage" => nil}} = body

      assert [
               %{
                 "message" => "Authentication required.",
                 "extensions" => %{"code" => "UNAUTHENTICATED"}
               }
             ] =
               body["errors"]
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A reply to a reply quotes only its immediate parent
    test "asking a quote for a quote is a document error, not an empty field", %{conn: conn} do
      response =
        post_graphql(
          conn,
          """
          query NestedQuote($roomSlug: String!) {
            familyChatMessages(roomSlug: $roomSlug) {
              nodes { replyTo { replyTo { id } } }
            }
          }
          """,
          %{"roomSlug" => FamilyChat.canonical_room_slug()}
        )

      body = Jason.decode!(response.resp_body)
      # Safe envelope: a document error, never an empty field and never the
      # validator's internals.
      assert [
               %{
                 "message" => "The request is invalid.",
                 "extensions" => %{"code" => "VALIDATION_FAILED"}
               }
             ] = body["errors"]
    end
  end

  describe "the safe transport envelope" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: The GraphQL endpoint refuses a malformed request before executing it
    test "a malformed JSON body answers the safe JSON envelope", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(@path, "this is not json Mr. X{{{ Best regards")

      assert response.status == 400
      assert json_content_type?(response)

      body = Jason.decode!(response.resp_body)

      assert [
               %{
                 "message" => "The request is invalid.",
                 "extensions" => %{"code" => "VALIDATION_FAILED"}
               }
             ] = body["errors"]
    end

    test "a non-string query answers only the safe envelope", %{conn: conn} do
      response = post_raw_graphql(conn, Jason.encode!(%{"query" => 42}))

      assert response.status == 200
      assert json_content_type?(response)

      body = Jason.decode!(response.resp_body)

      assert [
               %{
                 "message" => "The request is invalid.",
                 "extensions" => %{"code" => "VALIDATION_FAILED"}
               }
             ] = body["errors"]
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Invalid message text is rejected before commit
    test "an over-long body names its 4,000-character limit", %{conn: conn} do
      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => String.duplicate("a", 4_001)
        })

      assert response.status == 200

      body = Jason.decode!(response.resp_body)
      assert %{"data" => %{"sendFamilyChatMessage" => nil}} = body

      assert [
               %{
                 "message" => "The message exceeds the 4,000-character limit.",
                 "extensions" => %{"code" => "BODY_TOO_LONG"}
               }
             ] = body["errors"]
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Invalid message text is rejected before commit
    test "an over-large body names its 16 KiB limit", %{conn: conn} do
      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => String.duplicate("👨‍👩‍👧‍👦", 700)
        })

      assert response.status == 200

      body = Jason.decode!(response.resp_body)
      assert %{"data" => %{"sendFamilyChatMessage" => nil}} = body

      assert [
               %{
                 "message" => "The message exceeds the 16 KiB size limit.",
                 "extensions" => %{"code" => "BODY_TOO_LARGE"}
               }
             ] = body["errors"]
    end

    # Logout revokes the server-side session while the browser still holds its
    # cookie: the stale cookie authorizes nothing and commits nothing.
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: An unauthenticated visitor is denied family chat data
    test "a logged-out session authorizes nothing, even with its cookie", %{conn: conn} do
      token = Plug.Conn.fetch_cookies(conn).cookies["_bnest_identity"]
      assert :ok = BnestApp.Identity.logout(token)

      client_message_id = Ecto.UUID.generate()

      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => client_message_id,
          "body" => "should never commit",
          "replyToMessageId" => "1"
        })

      assert response.status == 200
      assert json_content_type?(response)

      body = Jason.decode!(response.resp_body)
      assert %{"data" => %{"sendFamilyChatMessage" => nil}} = body

      assert [
               %{
                 "message" => "Authentication required.",
                 "extensions" => %{"code" => "UNAUTHENTICATED"}
               }
             ] = body["errors"]

      assert RoomStore.find_message(
               SqliteRoomStore.new(),
               1,
               "user",
               test_user_id(),
               client_message_id
             ) == nil
    end
  end

  describe "familyChatRooms, familyChatRoom, and familyChatMessages queries" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member queries the authorized room list
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member queries Ruang Keluarga by its slug
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: The latest page is returned without a cursor
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A beforeId page returns older history
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: An afterId page returns catch-up history
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A message page request with invalid arguments is rejected
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A missing room is reported safely without enumerating hidden rooms
    test "lists rooms, reads the canonical room, pages latest, older, and newer, and hides missing rooms",
         %{conn: conn} do
      slug = FamilyChat.canonical_room_slug()

      response = post_graphql(conn, "query { familyChatRooms { slug name } }", %{})
      assert response.status == 200
      rooms = Jason.decode!(response.resp_body)
      refute Map.has_key?(rooms, "errors")

      assert rooms["data"]["familyChatRooms"] == [
               %{"slug" => "ruang-keluarga", "name" => "Ruang Keluarga"}
             ]

      response =
        post_graphql(
          conn,
          "query($slug: String!) { familyChatRoom(slug: $slug) { slug name } }",
          %{"slug" => slug}
        )

      assert response.status == 200
      room = Jason.decode!(response.resp_body)
      refute Map.has_key?(room, "errors")

      assert room["data"]["familyChatRoom"] == %{
               "slug" => "ruang-keluarga",
               "name" => "Ruang Keluarga"
             }

      response =
        post_graphql(
          conn,
          "query($slug: String!) { familyChatRoom(slug: $slug) { slug name } }",
          %{"slug" => "ruang-tidak-ada"}
        )

      assert response.status == 200
      missing = Jason.decode!(response.resp_body)
      assert missing["data"]["familyChatRoom"] == nil

      assert [
               %{
                 "message" => "The requested room is unavailable.",
                 "extensions" => %{"code" => "ROOM_NOT_FOUND"}
               }
             ] = missing["errors"]

      refute response.resp_body =~ "ruang-keluarga"

      user_id = test_user_id()

      ids =
        for n <- 1..3 do
          {:ok, message} =
            FamilyChat.send_message(
              user_id,
              slug,
              Ecto.UUID.generate(),
              "page #{n}"
            )

          message.id
        end

      page_query = """
      query($roomSlug: String!, $beforeId: ID, $afterId: ID, $limit: Int) {
        familyChatMessages(roomSlug: $roomSlug, beforeId: $beforeId, afterId: $afterId, limit: $limit) {
          nodes { id }
          hasOlder
          hasNewer
        }
      }
      """

      response =
        post_graphql(conn, page_query, %{
          "roomSlug" => slug,
          "beforeId" => nil,
          "afterId" => nil,
          "limit" => 50
        })

      assert response.status == 200
      latest = Jason.decode!(response.resp_body)
      refute Map.has_key?(latest, "errors")

      assert latest["data"]["familyChatMessages"] == %{
               "nodes" => Enum.map(ids, &%{"id" => to_string(&1)}),
               "hasOlder" => false,
               "hasNewer" => false
             }

      response =
        post_graphql(conn, page_query, %{
          "roomSlug" => slug,
          "beforeId" => List.last(ids),
          "afterId" => nil,
          "limit" => 50
        })

      assert response.status == 200
      older = Jason.decode!(response.resp_body)
      refute Map.has_key?(older, "errors")

      assert older["data"]["familyChatMessages"]["nodes"] ==
               ids |> Enum.take(2) |> Enum.map(&%{"id" => to_string(&1)})

      assert older["data"]["familyChatMessages"]["hasNewer"] == true

      response =
        post_graphql(conn, page_query, %{
          "roomSlug" => slug,
          "beforeId" => nil,
          "afterId" => hd(ids),
          "limit" => 50
        })

      assert response.status == 200
      newer = Jason.decode!(response.resp_body)
      refute Map.has_key?(newer, "errors")

      assert newer["data"]["familyChatMessages"]["nodes"] ==
               ids |> tl() |> Enum.map(&%{"id" => to_string(&1)})

      response =
        post_graphql(conn, page_query, %{
          "roomSlug" => slug,
          "beforeId" => nil,
          "afterId" => nil,
          "limit" => 0
        })

      assert response.status == 200
      invalid = Jason.decode!(response.resp_body)

      assert [%{"extensions" => %{"code" => "VALIDATION_FAILED"}}] = invalid["errors"]
    end
  end

  describe "sendFamilyChatMessage without a reply target" do
    @send_plain """
    mutation SendFamilyChatMessage(
      $roomSlug: String!
      $clientMessageId: ID!
      $body: String!
    ) {
      sendFamilyChatMessage(
        roomSlug: $roomSlug
        clientMessageId: $clientMessageId
        body: $body
      ) {
        id
        body
        senderDisplayName
      }
    }
    """

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member sends a message and gets the committed message back
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A sent message names its sender by display username, not raw user ID
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Retrying a client message ID returns the first commit
    test "commits a plain message naming its live sender and replays its client message id",
         %{conn: conn} do
      user_id = test_user_id()
      client_message_id = Ecto.UUID.generate()

      response =
        post_graphql(conn, @send_plain, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => client_message_id,
          "body" => "Dinner is ready"
        })

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      refute Map.has_key?(body, "errors")

      assert %{
               "data" => %{
                 "sendFamilyChatMessage" => %{
                   "id" => id,
                   "body" => "Dinner is ready",
                   "senderDisplayName" => display_name
                 }
               }
             } = body

      assert is_binary(id)
      assert display_name == BnestApp.Identity.display_name_for(user_id)

      retried =
        post_graphql(conn, @send_plain, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => client_message_id,
          "body" => "a different body"
        })

      assert retried.status == 200
      replayed = Jason.decode!(retried.resp_body)
      refute Map.has_key?(replayed, "errors")

      assert %{
               "data" => %{
                 "sendFamilyChatMessage" => %{"id" => ^id, "body" => "Dinner is ready"}
               }
             } = replayed
    end
  end

  describe "familyChatMessages bodyHtml" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A message carries its body as safe HTML
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Raw HTML in a message body is escaped in bodyHtml
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A page asks for each message's body HTML once
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: bodyHtml makes the same image decisions as the Codex chat
    test "a page carries each body as safe HTML with raw markup escaped", %{conn: conn} do
      user_id = test_user_id()
      slug = FamilyChat.canonical_room_slug()

      {:ok, _} =
        FamilyChat.send_message(user_id, slug, Ecto.UUID.generate(), "a **bold** note")

      {:ok, _} =
        FamilyChat.send_message(user_id, slug, Ecto.UUID.generate(), "a <b>raw</b> note")

      {:ok, _} =
        FamilyChat.send_message(
          user_id,
          slug,
          Ecto.UUID.generate(),
          "see ![pic](https://example.test/i.png)"
        )

      response =
        post_graphql(
          conn,
          "query($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug, limit: 50) { nodes { body bodyHtml } } }",
          %{"roomSlug" => slug}
        )

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      refute Map.has_key?(body, "errors")

      nodes = body["data"]["familyChatMessages"]["nodes"]
      bold = Enum.find(nodes, &(&1["body"] == "a **bold** note"))
      assert bold["bodyHtml"] =~ "<strong>bold</strong>"

      raw = Enum.find(nodes, &(&1["body"] == "a <b>raw</b> note"))
      assert raw["bodyHtml"] =~ "&lt;b&gt;"
      refute raw["bodyHtml"] =~ "<b>"

      pic = Enum.find(nodes, &(&1["body"] =~ "![pic]"))
      assert pic["bodyHtml"] =~ "<img"
      assert pic["bodyHtml"] =~ "https://example.test/i.png"
      assert pic["bodyHtml"] =~ "pic"
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A quote is shortened to a bounded preview
    test "a reply carries a bounded preview of a long target", %{conn: conn} do
      target = commit_target_with_body(String.duplicate("a", 400))

      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => "answers the long target",
          "replyToMessageId" => to_string(target.id)
        })

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      refute Map.has_key?(body, "errors")

      quoted = body["data"]["sendFamilyChatMessage"]["replyTo"]
      assert String.length(quoted["bodyPreview"]) == 161
      assert String.ends_with?(quoted["bodyPreview"], "…")
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A reply caught up through afterId carries its quote
    test "a catch-up page through afterId carries the reply's quote", %{conn: conn} do
      target = commit_target!()

      {:ok, reply} =
        FamilyChat.send_message(
          test_user_id(),
          FamilyChat.canonical_room_slug(),
          Ecto.UUID.generate(),
          "answers a",
          "Ayah",
          target.id
        )

      response =
        post_graphql(
          conn,
          "query($roomSlug: String!, $afterId: ID) { familyChatMessages(roomSlug: $roomSlug, afterId: $afterId, limit: 50) { nodes { id replyTo { id bodyPreview } } } }",
          %{"roomSlug" => FamilyChat.canonical_room_slug(), "afterId" => target.id}
        )

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      refute Map.has_key?(body, "errors")

      nodes = body["data"]["familyChatMessages"]["nodes"]
      found = Enum.find(nodes, &(&1["id"] == to_string(reply.id)))
      assert found["replyTo"]["id"] == to_string(target.id)
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Invalid message text is rejected before commit
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A reply target in a different room is rejected before commit
    test "a reply naming a message from another room is refused and commits nothing", %{
      conn: conn
    } do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      %{rows: _} =
        BnestApp.SqliteRepo.query!(
          "INSERT INTO family_chat_rooms (id, slug, name, room_kind, member_posting_enabled, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by) VALUES (900, 'ruang-arsip', 'Ruang Arsip', 'conversation', 1, ?, 'test', ?, 'test', ?, 'test')",
          [now, now, now]
        )

      {:ok, foreign} =
        FamilyChat.insert_message!(
          900,
          "user",
          "test-user-foreign-room",
          "Foreign",
          Ecto.UUID.generate(),
          "a message in another room"
        )

      client_message_id = Ecto.UUID.generate()

      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => client_message_id,
          "body" => "answers across rooms",
          "replyToMessageId" => to_string(foreign.id)
        })

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      assert %{"data" => %{"sendFamilyChatMessage" => nil}} = body

      assert [
               %{
                 "message" => "The request is invalid.",
                 "extensions" => %{"code" => "VALIDATION_FAILED"}
               }
             ] = body["errors"]

      assert RoomStore.find_message(
               SqliteRoomStore.new(),
               1,
               "user",
               test_user_id(),
               client_message_id
             ) == nil
    end

    test "a blank body is rejected before committing", %{conn: conn} do
      response =
        post_graphql(conn, @send_reply, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => "   "
        })

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      assert %{"data" => %{"sendFamilyChatMessage" => nil}} = body

      assert [
               %{
                 "message" => "The request is invalid.",
                 "extensions" => %{"code" => "VALIDATION_FAILED"}
               }
             ] = body["errors"]
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A page that asks for each message's body HTML under ten aliases is refused
    test "a page repeating bodyHtml under ten aliases is refused", %{conn: conn} do
      aliases = for n <- 1..10, do: "html#{n}: bodyHtml"

      response =
        post_graphql(
          conn,
          "query($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug, limit: 50) { nodes { id #{Enum.join(aliases, " ")} } } }",
          %{"roomSlug" => FamilyChat.canonical_room_slug()}
        )

      assert response.status == 200
      body = Jason.decode!(response.resp_body)

      assert [%{"extensions" => %{"code" => "VALIDATION_FAILED"}}] = body["errors"]
    end
  end

  describe "web push configuration and the session subscription lifecycle" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member reads the Web Push configuration
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member reads their current Web Push subscription state
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member enables Web Push for this device only
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A member disables Web Push on this device
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Disabling Web Push again still reports disabled
    test "configuration answers, and enable, read, disable, and re-disable stay per session",
         %{conn: conn} do
      response = post_graphql(conn, "query { webPushConfiguration { available } }", %{})
      assert response.status == 200
      config = Jason.decode!(response.resp_body)
      refute Map.has_key?(config, "errors")
      assert is_boolean(config["data"]["webPushConfiguration"]["available"])

      current_query = "query { currentWebPushSubscription { enabled } }"

      response = post_graphql(conn, current_query, %{})
      assert response.status == 200
      current = Jason.decode!(response.resp_body)
      refute Map.has_key?(current, "errors")
      assert current["data"]["currentWebPushSubscription"]["enabled"] == false

      endpoint = "https://push.allowed.example.com/test-user-" <> Ecto.UUID.generate()

      key = fn bytes -> :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false) end

      response =
        post_graphql(
          conn,
          "mutation($endpoint: String!, $p256dh: String!, $auth: String!) { upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { enabled } }",
          %{"endpoint" => endpoint, "p256dh" => key.(32), "auth" => key.(16)}
        )

      assert response.status == 200
      upserted = Jason.decode!(response.resp_body)
      refute Map.has_key?(upserted, "errors")
      assert upserted["data"]["upsertWebPushSubscription"]["enabled"] == true

      response = post_graphql(conn, current_query, %{})
      assert response.status == 200
      enabled = Jason.decode!(response.resp_body)
      assert enabled["data"]["currentWebPushSubscription"]["enabled"] == true

      disable = "mutation { disableCurrentWebPushSubscription { enabled } }"

      response = post_graphql(conn, disable, %{})
      assert response.status == 200
      disabled = Jason.decode!(response.resp_body)
      refute Map.has_key?(disabled, "errors")
      assert disabled["data"]["disableCurrentWebPushSubscription"]["enabled"] == false

      response = post_graphql(conn, disable, %{})
      assert response.status == 200
      again = Jason.decode!(response.resp_body)
      refute Map.has_key?(again, "errors")
      assert again["data"]["disableCurrentWebPushSubscription"]["enabled"] == false

      response = post_graphql(conn, current_query, %{})
      assert response.status == 200
      current = Jason.decode!(response.resp_body)
      assert current["data"]["currentWebPushSubscription"]["enabled"] == false
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: An unsafe Web Push subscription endpoint is rejected
    test "an unsafe endpoint is refused and stores nothing", %{conn: conn} do
      for endpoint <- [
            "http://push.example.com/unapproved-host",
            "https://203.0.113.7/ip-literal-endpoint",
            "https://push.allowed.example.com:8443/nondefault-port",
            "https://user@push.allowed.example.com/userinfo-present"
          ] do
        response =
          post_graphql(
            conn,
            "mutation($endpoint: String!, $p256dh: String!, $auth: String!) { upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { enabled } }",
            %{"endpoint" => endpoint, "p256dh" => "probe-p256dh", "auth" => "probe-auth"}
          )

        assert response.status == 200
        body = Jason.decode!(response.resp_body)

        assert [
                 %{
                   "message" => "The request is invalid.",
                   "extensions" => %{"code" => "VALIDATION_FAILED"}
                 }
               ] = body["errors"]

        assert body["data"]["upsertWebPushSubscription"] == nil
      end

      response =
        post_graphql(conn, "query { currentWebPushSubscription { enabled } }", %{})

      assert response.status == 200
      current = Jason.decode!(response.resp_body)
      assert current["data"]["currentWebPushSubscription"]["enabled"] == false
    end
  end

  describe "sendFamilyChatMessage without a CSRF token" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A mutation without a valid CSRF token is rejected
    test "a mutation without a CSRF token is rejected before executing", %{conn: conn} do
      # `build_conn/0` disables CSRF protection for tests; the rejection only
      # shows with the protection switched back on.
      response =
        conn
        |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
        |> post_graphql(@send_plain, %{
          "roomSlug" => FamilyChat.canonical_room_slug(),
          "clientMessageId" => Ecto.UUID.generate(),
          "body" => "should never commit"
        })

      assert response.status == 403
      body = Jason.decode!(response.resp_body)

      assert [
               %{
                 "message" => "Missing or invalid CSRF token.",
                 "extensions" => %{"code" => "CSRF_REJECTED"}
               }
             ] = body["errors"]
    end
  end

  describe "GraphiQL availability" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A production endpoint does not serve GraphiQL
    test "a build without dev routes serves no GraphiQL page", %{conn: conn} do
      refute BnestAppWeb.DevRoutes.mounted?(Application.get_env(:bnest_app, :dev_routes))

      assert get(conn, "/api/graphiql").status == 404
    end
  end

  describe "public schema introspection" do
    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: The public GraphQL schema exposes no system-message mutation
    test "introspection declares no field that posts a system message", %{conn: conn} do
      response =
        post_graphql(conn, "{ __schema { mutationType { fields { name } } } }", %{})

      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      refute Map.has_key?(body, "errors")

      names =
        body
        |> get_in(["data", "__schema", "mutationType", "fields"])
        |> Enum.map(& &1["name"])

      assert names != []
      assert Enum.all?(names, &(not String.contains?(&1, "ystem")))
    end
  end

  defp commit_target_with_body(body) do
    sender = "test-user-family-chat-boundary-" <> Ecto.UUID.generate()

    {:ok, target} =
      FamilyChat.send_message(
        sender,
        FamilyChat.canonical_room_slug(),
        Ecto.UUID.generate(),
        body,
        "Ayah"
      )

    target
  end

  defp commit_target! do
    sender = "test-user-family-chat-boundary-" <> Ecto.UUID.generate()

    {:ok, target} =
      FamilyChat.send_message(
        sender,
        FamilyChat.canonical_room_slug(),
        Ecto.UUID.generate(),
        "Nanti aku jemput jam 5",
        "Ayah"
      )

    target
  end

  # `Phoenix.ConnTest.post/3` multipart-encodes a plain map body by default;
  # the real boundary requires genuine `application/json`, so this sends what a
  # real client sends rather than what ConnTest defaults to.
  defp post_graphql(conn, query, variables) do
    post_raw_graphql(conn, Jason.encode!(%{"query" => query, "variables" => variables}))
  end

  defp post_raw_graphql(conn, body) do
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(@path, body)
  end

  defp json_content_type?(conn) do
    conn
    |> get_resp_header("content-type")
    |> Enum.any?(&String.starts_with?(&1, "application/json"))
  end

  # Resolved the same way the boundary resolves it: from a real session, not
  # from a guessed id -- so the "nothing committed" assertion looks where a
  # genuine commit would actually have landed.
  defp test_user_id do
    {username, password} = test_credentials()
    {:ok, token} = BnestApp.Identity.login(username, password)
    {:ok, %{"userId" => user_id}} = BnestApp.Identity.current_user(token)
    user_id
  end
end
