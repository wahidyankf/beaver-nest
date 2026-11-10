defmodule BnestAppWeb.ChatImageController do
  @moduledoc """
  Serves one repository image that a Codex reply shows (ADR 002, Decision 2). The route sits in the
  signed-in browser scope, so a signed-out visitor is redirected to log in first.

  The router has already percent-decoded each `*path` segment once. The segments are joined with
  `/` and passed on unchanged: the facade and the adapter decide what the path may name, and
  nothing here decodes it again.

  Every answer carries the same two headers, `cache-control` and a `sandbox` content security
  policy. A refusal is an empty `404` with the same headers, so the route does not reveal which
  files exist. No request value is echoed back in a header.
  """

  use BnestAppWeb, :controller

  alias BnestApp.CodexChat

  @cache_control "private, max-age=60"
  @content_security_policy "default-src 'none'; sandbox"

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"path" => segments}) do
    case CodexChat.repository_image(Enum.join(segments, "/")) do
      {:ok, content_type, bytes} ->
        conn
        |> put_security_headers()
        |> put_resp_content_type(content_type, nil)
        |> send_resp(:ok, bytes)

      :error ->
        conn
        |> put_security_headers()
        |> put_resp_content_type("text/plain", nil)
        |> send_resp(:not_found, "")
    end
  end

  defp put_security_headers(conn) do
    conn
    |> put_resp_header("cache-control", @cache_control)
    |> put_resp_header("content-security-policy", @content_security_policy)
  end
end
