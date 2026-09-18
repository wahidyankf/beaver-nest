defmodule BnestAppWeb.Plugs.GraphQLPipeline do
  @moduledoc """
  The `/api/graphql` HTTP boundary, implementing tech-doc 008's HTTP Pipeline
  exactly: method/content-type/size checks before resolver execution, CSRF
  validation on every cookie-authenticated POST, and safe (non-leaking) JSON
  error envelopes on every rejection — never Phoenix's default HTML/generic
  error renderer, so transport failures stay in the same envelope shape as
  GraphQL errors.
  """

  import Plug.Conn

  @max_body_bytes 64 * 1024

  def init(opts), do: opts

  def call(conn, _opts) do
    with :ok <- check_method(conn),
         :ok <- check_content_type(conn),
         :ok <- check_body_size(conn),
         :ok <- check_csrf(conn) do
      conn
    else
      {:reject, status, code} -> reject(conn, status, code)
    end
  end

  defp check_method(%{method: "POST"}), do: :ok
  defp check_method(_conn), do: {:reject, 405, "METHOD_NOT_ALLOWED"}

  defp check_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _rest] ->
        if String.starts_with?(content_type, "application/json"),
          do: :ok,
          else: {:reject, 415, "UNSUPPORTED_MEDIA_TYPE"}

      [] ->
        {:reject, 415, "UNSUPPORTED_MEDIA_TYPE"}
    end
  end

  defp check_body_size(conn) do
    case get_req_header(conn, "content-length") do
      [length] ->
        case Integer.parse(length) do
          {bytes, ""} when bytes > @max_body_bytes -> {:reject, 413, "PAYLOAD_TOO_LARGE"}
          _within_or_unknown -> :ok
        end

      [] ->
        :ok
    end
  end

  # Cookie-authenticated GraphQL POSTs require a valid same-origin CSRF token
  # (tech-doc 008). `Plug.CSRFProtection` reads it from the `x-csrf-token`
  # header when absent from params, matching the browser's fetch contract.
  defp check_csrf(conn) do
    Plug.CSRFProtection.call(conn, Plug.CSRFProtection.init([]))
    :ok
  rescue
    _invalid_csrf in [
      Plug.CSRFProtection.InvalidCSRFTokenError,
      Plug.CSRFProtection.InvalidCrossOriginRequestError
    ] ->
      {:reject, 403, "CSRF_REJECTED"}
  end

  defp reject(conn, status, code) do
    body =
      Jason.encode!(%{
        "errors" => [%{"message" => safe_message(code), "extensions" => %{"code" => code}}]
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
    |> halt()
  end

  defp safe_message("METHOD_NOT_ALLOWED"), do: "Method not allowed."
  defp safe_message("UNSUPPORTED_MEDIA_TYPE"), do: "Unsupported media type."
  defp safe_message("PAYLOAD_TOO_LARGE"), do: "Request payload too large."
  defp safe_message("CSRF_REJECTED"), do: "Missing or invalid CSRF token."
end
