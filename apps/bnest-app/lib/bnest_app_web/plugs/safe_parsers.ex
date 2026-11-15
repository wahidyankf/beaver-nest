defmodule BnestAppWeb.Plugs.SafeParsers do
  @moduledoc """
  The endpoint's body parsers with a safe envelope for the GraphQL API.

  A malformed JSON body dies in `Plug.Parsers` before the router (and the
  GraphQL pipeline's envelope) ever runs, so without this wrapper Phoenix's
  error renderer would answer it — and the test client would see the raise.
  This plug parses exactly like `Plug.Parsers` and, only for `/api/graphql`,
  answers a malformed body (`Plug.Parsers.ParseError`) or a body over the
  parsers' own cap (`Plug.Parsers.RequestTooLargeError`) with the same safe
  JSON envelope the GraphQL pipeline uses, instead of raising. Every other
  path reraises, keeping the default error rendering.
  """

  @behaviour Plug

  alias BnestAppWeb.Plugs.GraphQLPipeline

  @graphql_path "/api/graphql"

  @impl Plug
  def init(opts), do: Plug.Parsers.init(opts)

  @impl Plug
  def call(conn, opts) do
    Plug.Parsers.call(conn, opts)
  rescue
    error in [Plug.Parsers.ParseError, Plug.Parsers.RequestTooLargeError] ->
      if conn.request_path == @graphql_path do
        GraphQLPipeline.transport_reject(conn, error)
      else
        reraise error, __STACKTRACE__
      end
  end
end
