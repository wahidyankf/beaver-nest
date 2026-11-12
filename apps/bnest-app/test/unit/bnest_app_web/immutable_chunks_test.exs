defmodule BnestAppWeb.ImmutableChunksTest do
  # ADR 004, Decision 3: the diagram engine's chunks are named by their content hash, so a cached chunk never goes
  # stale. They are the only files that get a one-year, immutable cache lifetime.
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias BnestAppWeb.ImmutableChunks

  @immutable "public, max-age=31536000, immutable"

  # The header is written when the response is sent (the plug registers a before-send callback), so the test sends it.
  defp cache_control(path) do
    conn =
      conn(:get, path)
      |> ImmutableChunks.call(ImmutableChunks.init([]))
      |> send_resp(200, "")

    Plug.Conn.get_resp_header(conn, "cache-control")
  end

  test "a content-hashed diagram chunk is cached for a year, as immutable" do
    assert cache_control("/assets/js/diagrams/chunks/engine_core-4kZ9Qa.js") == [@immutable]
  end

  test "a diagram chunk without a content hash gets no lifetime from this plug" do
    refute @immutable in cache_control("/assets/js/diagrams/chunks/engine_core.js")
  end

  test "other assets get no lifetime from this plug" do
    refute @immutable in cache_control("/assets/js/app.js")
    refute @immutable in cache_control("/assets/js/diagrams/engine.js")
  end
end
