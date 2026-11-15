defmodule BnestAppWeb.GeneratedImageController do
  @moduledoc """
  Serves one Codex-generated image that a Codex reply shows (ADR 007, Decision 2). The route sits
  in the signed-in browser scope, so a signed-out visitor is redirected to log in first.

  The router has already percent-decoded each `*path` segment once. The segments are joined with
  `/` and passed on unchanged: the facade and the adapter decide what the two-segment
  `<thread>/<file>` reference may name, and nothing here decodes it again. Only the Codex room
  ever links here, through the `:codex_images` renderer option; Family Chat and every other
  caller withhold the same reference as text.

  Every answer carries the same two headers, `cache-control` and a `sandbox` content security
  policy. A refusal is an empty `404` with the same headers, so the route does not reveal which
  generations exist. No request value is echoed back in a header.
  """

  use BnestAppWeb, :controller

  alias BnestApp.CodexChat

  @cache_control "private, max-age=60"
  @content_security_policy "default-src 'none'; sandbox"

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"path" => segments}) when is_list(segments) do
    # The router split the raw path before decoding each segment once, so one encoded
    # segment can hold the slash: joining first makes both URL forms the same reference,
    # the way `ChatImageController` does. Only a strict two-segment `<thread>/<file>`
    # shape reaches the facade.
    case String.split(Enum.join(segments, "/"), "/") do
      [thread, file] ->
        case CodexChat.generated_image(thread, file) do
          {:ok, content_type, bytes} ->
            conn
            |> put_security_headers()
            |> put_resp_content_type(content_type, nil)
            |> send_resp(:ok, bytes)

          :error ->
            refuse(conn)
        end

      _other ->
        refuse(conn)
    end
  end

  def show(conn, _params), do: refuse(conn)

  # Every refusal is the same empty 404, so the route does not reveal which generations exist.
  defp refuse(conn) do
    conn
    |> put_security_headers()
    |> put_resp_content_type("text/plain", nil)
    |> send_resp(:not_found, "")
  end

  defp put_security_headers(conn) do
    conn
    |> put_resp_header("cache-control", @cache_control)
    |> put_resp_header("content-security-policy", @content_security_policy)
  end
end
