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

  @doc """
  Answers a body the endpoint parsers could not decode with this route's safe
  JSON envelope: a malformed body is a 400 `VALIDATION_FAILED`, a body over the
  parsers' own cap a 413 `PAYLOAD_TOO_LARGE`. Used by `SafeParsers`, which runs
  before the router, so transport failures keep the envelope shape the pipeline
  itself uses for every rejection.
  """
  @spec transport_reject(Plug.Conn.t(), Exception.t()) :: Plug.Conn.t()
  def transport_reject(conn, %Plug.Parsers.RequestTooLargeError{}) do
    reject(conn, 413, "PAYLOAD_TOO_LARGE")
  end

  def transport_reject(conn, %Plug.Parsers.ParseError{}) do
    reject(conn, 400, "VALIDATION_FAILED")
  end

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
        case Integer.parse(String.trim(length)) do
          {bytes, ""} when bytes > @max_body_bytes -> {:reject, 413, "PAYLOAD_TOO_LARGE"}
          _within_or_unknown -> :ok
        end

      [] ->
        check_unsized_body(conn)

      [_duplicate | _rest] ->
        {:reject, 413, "PAYLOAD_TOO_LARGE"}
    end
  end

  # A chunked upload carries no content-length, so the header alone cannot bound
  # it. After the endpoint parsers the decoded params are what Absinthe will
  # process, so their size is the meaningful bound; before parsing (a direct
  # pipeline call) the raw bytes are read with the same cap. Either way a body
  # over the cap is refused before the CSRF check.
  defp check_unsized_body(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} -> check_raw_body(conn)
      params -> check_decoded_body(params)
    end
  end

  defp check_decoded_body(params) do
    case Jason.encode(params) do
      {:ok, encoded} when byte_size(encoded) > @max_body_bytes ->
        {:reject, 413, "PAYLOAD_TOO_LARGE"}

      _within_or_unencodable ->
        :ok
    end
  end

  defp check_raw_body(conn) do
    case Plug.Conn.read_body(conn, length: @max_body_bytes + 1) do
      {:ok, body, _conn} when byte_size(body) > @max_body_bytes ->
        {:reject, 413, "PAYLOAD_TOO_LARGE"}

      {:more, _partial, _conn} ->
        {:reject, 413, "PAYLOAD_TOO_LARGE"}

      _within ->
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
  defp safe_message("VALIDATION_FAILED"), do: "The request is invalid."
end
