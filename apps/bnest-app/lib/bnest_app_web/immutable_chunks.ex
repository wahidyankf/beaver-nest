defmodule BnestAppWeb.ImmutableChunks do
  @moduledoc """
  Gives the diagram engine's content-hashed chunks (`assets/js/diagrams/chunks/<name>-<hash>.js`, ADR 004,
  Decision 3) a cache lifetime of one year. A chunk's name changes with its content, so a cached copy never goes stale.
  Every other path gets no header from this plug. It runs before `Plug.Static` in the endpoint, and `Plug.Static`
  writes its own `cache-control` for the file it serves, so the header is set when the response is sent, after
  that write. Only a served chunk (status 200 or 304) gets it; a missing chunk is a 404 and gets none.
  """

  @behaviour Plug

  import Plug.Conn

  @chunk_path ~r{\A/assets/js/diagrams/chunks/[A-Za-z0-9_]+-[A-Za-z0-9_-]+\.js\z}

  @impl Plug
  def init(options), do: options

  @immutable "public, max-age=31536000, immutable"

  @impl Plug
  def call(%Plug.Conn{request_path: path} = conn, _options) do
    if Regex.match?(@chunk_path, path),
      do: register_before_send(conn, &put_lifetime/1),
      else: conn
  end

  defp put_lifetime(%Plug.Conn{status: status} = conn) when status in [200, 304],
    do: put_resp_header(conn, "cache-control", @immutable)

  defp put_lifetime(conn), do: conn
end
