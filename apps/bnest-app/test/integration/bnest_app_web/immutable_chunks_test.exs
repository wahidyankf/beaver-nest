defmodule BnestAppWeb.ImmutableChunksIntegrationTest do
  # ADR 004, Decision 3: a content-hashed chunk keeps its one-year lifetime through `Plug.Static`, which writes its own
  # cache header for a file it serves. It needs a real file on disk, so it is an integration test (the unit boundary
  # refuses filesystem access).
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias BnestAppWeb.ImmutableChunks

  @immutable "public, max-age=31536000, immutable"

  # The endpoint's order (endpoint.ex): the chunk plug, then Plug.Static. The fixture is a real file in a temporary
  # directory, served by the same Plug.Static options the endpoint uses for its static paths.
  @tag :tmp_dir
  test "a served chunk keeps its one-year lifetime", %{tmp_dir: dir} do
    chunks = Path.join(dir, "assets/js/diagrams/chunks")
    File.mkdir_p!(chunks)
    File.write!(Path.join(chunks, "engine_core-4kZ9Qa.js"), "export {};")
    static = Plug.Static.init(at: "/", from: dir, gzip: false, only: ["assets"])

    conn =
      conn(:get, "/assets/js/diagrams/chunks/engine_core-4kZ9Qa.js")
      |> ImmutableChunks.call(ImmutableChunks.init([]))
      |> Plug.Static.call(static)

    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == [@immutable]
  end
end
