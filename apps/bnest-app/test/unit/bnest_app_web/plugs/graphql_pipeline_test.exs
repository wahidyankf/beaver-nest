defmodule BnestAppWeb.Plugs.GraphQLPipelineTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.Plugs.GraphQLPipeline

  # A request shaped like a chunked upload: no content-length header, so only
  # the actual body can bound it.
  defp chunked_conn(body) do
    Plug.Test.conn(:post, "/api/graphql", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.delete_req_header("content-length")
    |> Plug.Conn.put_req_header("transfer-encoding", "chunked")
    |> Plug.Test.init_test_session(%{})
  end

  defp code(conn) do
    %{"errors" => [%{"extensions" => %{"code" => code}}]} = Jason.decode!(conn.resp_body)
    code
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A non-POST request is 405, a non-JSON content type is 415
  test "a non-POST request is 405 and a non-JSON content type is 415, with no GraphQL data" do
    get_conn =
      GraphQLPipeline.call(
        Plug.Test.conn(:get, "/api/graphql")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Test.init_test_session(%{}),
        []
      )

    assert get_conn.halted
    assert get_conn.status == 405
    assert code(get_conn) == "METHOD_NOT_ALLOWED"
    refute Map.has_key?(Jason.decode!(get_conn.resp_body), "data")

    text_conn =
      GraphQLPipeline.call(
        Plug.Test.conn(:post, "/api/graphql", "{}")
        |> Plug.Conn.put_req_header("content-type", "text/plain")
        |> Plug.Test.init_test_session(%{}),
        []
      )

    assert text_conn.halted
    assert text_conn.status == 415
    assert code(text_conn) == "UNSUPPORTED_MEDIA_TYPE"
    refute Map.has_key?(Jason.decode!(text_conn.resp_body), "data")
  end

  test "a chunked body over 64 KiB is rejected before the CSRF check" do
    result = GraphQLPipeline.call(chunked_conn(String.duplicate("a", 70 * 1024)), [])

    assert result.halted
    assert result.status == 413
    assert code(result) == "PAYLOAD_TOO_LARGE"
  end

  test "a chunked body within budget passes the size gate" do
    result = GraphQLPipeline.call(chunked_conn(Jason.encode!(%{"query" => "{ __typename }"})), [])

    assert result.halted
    assert result.status == 403
    assert code(result) == "CSRF_REJECTED"
  end

  test "a content-length over 64 KiB is rejected" do
    result =
      GraphQLPipeline.call(
        Plug.Test.conn(:post, "/api/graphql", "x")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("content-length", Integer.to_string(65 * 1024))
        |> Plug.Test.init_test_session(%{}),
        []
      )

    assert result.halted
    assert result.status == 413
    assert code(result) == "PAYLOAD_TOO_LARGE"
  end

  test "duplicate content-length headers are rejected rather than trusted" do
    result =
      GraphQLPipeline.call(
        Plug.Test.conn(:post, "/api/graphql", "x")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.prepend_req_headers([{"content-length", "10"}, {"content-length", "20"}])
        |> Plug.Test.init_test_session(%{}),
        []
      )

    assert result.halted
    assert result.status == 413
    assert code(result) == "PAYLOAD_TOO_LARGE"
  end

  # After the endpoint parsers the decoded params are what Absinthe will
  # process, so their size is the meaningful bound for a body that arrived
  # without a content-length.
  defp parsed_conn(params) do
    Plug.Test.conn(:post, "/api/graphql", "")
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.delete_req_header("content-length")
    |> Map.put(:body_params, params)
    |> Plug.Test.init_test_session(%{})
  end

  test "an already-parsed body over 64 KiB is rejected before the CSRF check" do
    result = GraphQLPipeline.call(parsed_conn(%{"query" => String.duplicate("a", 70 * 1024)}), [])

    assert result.halted
    assert result.status == 413
    assert code(result) == "PAYLOAD_TOO_LARGE"
  end

  test "an already-parsed body within budget passes the size gate" do
    result = GraphQLPipeline.call(parsed_conn(%{"query" => "{ __typename }"}), [])

    assert result.halted
    assert result.status == 403
    assert code(result) == "CSRF_REJECTED"
  end
end
