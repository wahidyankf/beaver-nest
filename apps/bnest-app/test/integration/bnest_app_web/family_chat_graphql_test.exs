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
    {:ok, _room} = FamilyChat.Store.migrate!()
    {:ok, conn: conn}
  end

  describe "sendFamilyChatMessage with a reply target" do
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

      assert FamilyChat.Store.find_message(1, "user", test_user_id(), client_message_id) == nil
    end

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
      assert [%{"message" => message} | _rest] = body["errors"]
      assert message =~ "replyTo"
    end
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
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(@path, Jason.encode!(%{"query" => query, "variables" => variables}))
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
