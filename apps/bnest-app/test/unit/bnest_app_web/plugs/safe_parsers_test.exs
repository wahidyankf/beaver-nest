defmodule BnestAppWeb.Plugs.SafeParsersTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.Plugs.SafeParsers

  defp opts(extra \\ []) do
    SafeParsers.init(
      Keyword.merge(
        [parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason],
        extra
      )
    )
  end

  defp json_conn(path, body) do
    Plug.Test.conn(:post, path, body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  defp code(conn) do
    %{"errors" => [%{"extensions" => %{"code" => code}}]} = Jason.decode!(conn.resp_body)
    code
  end

  test "a valid JSON body on /api/graphql parses untouched" do
    conn = json_conn("/api/graphql", Jason.encode!(%{"query" => "{ __typename }"}))

    result = SafeParsers.call(conn, opts())

    refute result.halted
    assert result.params["query"] == "{ __typename }"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: The GraphQL endpoint refuses a malformed request before executing it
  test "a malformed JSON body on /api/graphql answers 400 VALIDATION_FAILED" do
    conn = json_conn("/api/graphql", "this is not json")

    result = SafeParsers.call(conn, opts())

    assert result.halted
    assert result.status == 400
    assert code(result) == "VALIDATION_FAILED"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: The GraphQL endpoint refuses a malformed request before executing it
  test "a body over the parsers cap on /api/graphql answers 413 PAYLOAD_TOO_LARGE" do
    conn = json_conn("/api/graphql", Jason.encode!(%{"query" => "{ __typename }"}))

    result = SafeParsers.call(conn, opts(length: 10))

    assert result.halted
    assert result.status == 413
    assert code(result) == "PAYLOAD_TOO_LARGE"
  end

  test "a malformed body off /api/graphql reraises for the default renderer" do
    conn = json_conn("/other", "this is not json")

    assert_raise Plug.Parsers.ParseError, fn -> SafeParsers.call(conn, opts()) end
  end
end
