defmodule BnestAppWeb.GraphQLTransportTest do
  @moduledoc """
  The `/api/graphql` transport boundary and the unauthenticated push
  contract at the real endpoint, in process.

  Runs the genuine Plug pipeline -- endpoint, router, CSRF/session plugs, and
  `Absinthe.Plug` -- so a rejection carries the envelope the API standard
  names. No session is ever signed in here: both scenarios prove what a
  caller without one receives.
  """

  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  @path "/api/graphql"

  defp post_graphql(conn, query, variables) do
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(@path, Jason.encode!(%{"query" => query, "variables" => variables}))
  end

  defp refused_code(body) do
    assert [%{"extensions" => %{"code" => code}}] = body["errors"]
    code
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A non-POST request is 405, a non-JSON content type is 415
  @tag :unauthenticated
  test "a non-POST request is 405 and a non-JSON content type is 415, with no data", %{conn: conn} do
    get_response = get(conn, @path)

    assert get_response.status == 405
    get_body = Jason.decode!(get_response.resp_body)
    assert refused_code(get_body) == "METHOD_NOT_ALLOWED"
    refute Map.has_key?(get_body, "data")

    text_response =
      conn
      |> Plug.Conn.put_req_header("content-type", "text/plain")
      |> post(@path, "{}")

    assert text_response.status == 415
    text_body = Jason.decode!(text_response.resp_body)
    assert refused_code(text_body) == "UNSUPPORTED_MEDIA_TYPE"
    refute Map.has_key?(text_body, "data")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Push queries and mutations refuse unauthenticated callers
  @tag :unauthenticated
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A visitor with no session is refused every Web Push subscription operation
  test "push queries and mutations without a session are unauthenticated", %{conn: conn} do
    variables = %{
      "endpoint" => "https://push.allowed.example.com/transport-probe",
      "p256dh" => "probe-p256dh",
      "auth" => "probe-auth"
    }

    upsert =
      post_graphql(
        conn,
        "mutation Upsert($endpoint: String!, $p256dh: String!, $auth: String!) { upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { enabled } }",
        variables
      )

    assert upsert.status == 200
    upsert_body = Jason.decode!(upsert.resp_body)
    assert refused_code(upsert_body) == "UNAUTHENTICATED"
    assert upsert_body["data"]["upsertWebPushSubscription"] == nil

    disable =
      post_graphql(
        conn,
        "mutation { disableCurrentWebPushSubscription { enabled } }",
        %{}
      )

    assert disable.status == 200
    disable_body = Jason.decode!(disable.resp_body)
    assert refused_code(disable_body) == "UNAUTHENTICATED"

    current =
      post_graphql(
        conn,
        "query { currentWebPushSubscription { enabled } }",
        %{}
      )

    assert current.status == 200
    current_body = Jason.decode!(current.resp_body)
    assert refused_code(current_body) == "UNAUTHENTICATED"

    configuration =
      post_graphql(conn, "query { webPushConfiguration { available } }", %{})

    assert configuration.status == 200
    configuration_body = Jason.decode!(configuration.resp_body)
    assert configuration_body["errors"] == nil
    assert is_boolean(configuration_body["data"]["webPushConfiguration"]["available"])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A signed-in session with no session digest is refused every Web Push subscription operation
  @tag :unauthenticated
  test "a session without a digest authorizes nothing", %{conn: conn} do
    sessioned =
      Plug.Test.init_test_session(conn, %{"current_user" => %{"userId" => "user-digestless"}})

    current =
      post_graphql(sessioned, "query { currentWebPushSubscription { enabled } }", %{})

    assert current.status == 200
    assert refused_code(Jason.decode!(current.resp_body)) == "UNAUTHENTICATED"
    assert Jason.decode!(current.resp_body)["data"]["currentWebPushSubscription"] == nil

    upsert =
      post_graphql(
        sessioned,
        "mutation Upsert($endpoint: String!, $p256dh: String!, $auth: String!) { upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { enabled } }",
        %{
          "endpoint" => "https://push.allowed.example.com/transport-digestless",
          "p256dh" => "probe-p256dh",
          "auth" => "probe-auth"
        }
      )

    assert upsert.status == 200
    assert refused_code(Jason.decode!(upsert.resp_body)) == "UNAUTHENTICATED"
  end
end
