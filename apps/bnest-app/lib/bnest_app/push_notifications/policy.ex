defmodule BnestApp.PushNotifications.Policy do
  @moduledoc """
  Pure parse/shape/allowlist policy for Web Push (tech-doc 004). No SQL, no
  network egress, no process/filesystem access -- every function here is a
  plain data transform so it is provable at the unit layer without a real
  database or HTTP boundary.

  Validation order matters (tech-doc 004): this module owns "pure
  parse/shape/allowlist first"; `BnestApp.PushNotifications` performs the
  database mutation second; `BnestApp.PushNotifications.Sender` performs
  egress only inside the dispatcher, never here.
  """

  @max_endpoint_bytes 2048
  @max_key_bytes 256
  @max_auth_bytes 128
  @body_grapheme_limit 120

  # Exact Apple/Mozilla/Chromium Web Push endpoint hosts (tech-doc 004: "Delivery
  # revalidates current Apple, Mozilla, and Chromium endpoint guidance before
  # manifest changes"). `push.allowed.example.com` is a test-only synthetic
  # provider host (never dialed against a real network -- the dispatcher's own
  # loopback/allowlist fixtures in test env point real traffic at a local
  # sender double instead), present only when `Mix.env() == :test` so this
  # exact list is what ships to production.
  @production_hosts ~w(
    web.push.apple.com
    updates.push.services.mozilla.com
    fcm.googleapis.com
    android.googleapis.com
  )

  @spec allowlisted_hosts() :: [String.t()]
  def allowlisted_hosts do
    if Application.get_env(:bnest_app, :push_notifications_test_provider?, false) do
      @production_hosts ++ ~w(push.allowed.example.com)
    else
      @production_hosts
    end
  end

  @doc """
  Validates a browser-supplied subscription input map before any database
  write. Returns the exact three fields the schema stores, normalized, or a
  safe validation-failure reason atom -- never a raw parse exception.
  """
  @spec validate_subscription_input(map()) ::
          {:ok, %{endpoint: String.t(), p256dh: String.t(), auth: String.t()}}
          | {:error, atom()}
  def validate_subscription_input(input) when is_map(input) do
    allowed_keys = ~w(endpoint p256dh auth)

    if Enum.all?(Map.keys(input), &(&1 in allowed_keys)) do
      with {:ok, endpoint} <- fetch_binary(input, "endpoint"),
           {:ok, p256dh} <- fetch_binary(input, "p256dh"),
           {:ok, auth} <- fetch_binary(input, "auth"),
           :ok <- validate_endpoint(endpoint),
           :ok <- validate_key_shape(p256dh, @max_key_bytes),
           :ok <- validate_key_shape(auth, @max_auth_bytes) do
        {:ok, %{endpoint: endpoint, p256dh: p256dh, auth: auth}}
      end
    else
      {:error, :unknown_input_key}
    end
  end

  def validate_subscription_input(_input), do: {:error, :invalid_shape}

  @doc "SHA-256 hex digest of an endpoint URL, used as the stored unique key (never the raw endpoint in a unique index)."
  @spec endpoint_digest(String.t()) :: String.t()
  def endpoint_digest(endpoint) when is_binary(endpoint),
    do: :crypto.hash(:sha256, endpoint) |> Base.encode16(case: :lower)

  @doc "Builds the exact payload shape tech-doc 004 specifies. `sender_display_name` is the committed snapshot; `body` is collapsed/truncated to 120 graphemes with one ellipsis."
  @spec build_payload(pos_integer(), String.t(), String.t(), String.t()) :: map()
  def build_payload(message_id, sender_display_name, body, room_slug) do
    %{
      "type" => "family-chat-message",
      "messageId" => message_id,
      "title" => sender_display_name,
      "body" => truncate_body(body),
      "tag" => "family-chat-message-" <> Integer.to_string(message_id),
      "url" => "/family-chat/" <> room_slug
    }
  end

  @doc "Collapses whitespace and truncates to 120 graphemes with one trailing ellipsis when the source is longer."
  @spec truncate_body(String.t()) :: String.t()
  def truncate_body(body) do
    collapsed = body |> String.split(~r/\s+/u, trim: true) |> Enum.join(" ")
    graphemes = String.graphemes(collapsed)

    if length(graphemes) > @body_grapheme_limit do
      graphemes |> Enum.take(@body_grapheme_limit - 1) |> Enum.join() |> Kernel.<>("…")
    else
      collapsed
    end
  end

  @doc "Classifies a completed HTTP attempt (status code or transport-error atom) into tech-doc 004's delivery-result table."
  @spec classify_result({:status, non_neg_integer()} | {:transport, atom()}) ::
          :delivered | :gone | :terminal | :retryable
  def classify_result({:status, status}) when status in 200..299, do: :delivered
  def classify_result({:status, status}) when status in [404, 410], do: :gone
  def classify_result({:status, status}) when status in 300..399, do: :terminal
  def classify_result({:status, status}) when status in 400..499, do: :terminal
  def classify_result({:status, status}) when status in 500..599, do: :retryable
  def classify_result({:transport, _reason}), do: :retryable

  @backoff_seconds [30, 120, 480, 1920]
  @max_attempts 5
  @ceiling_seconds 3_600

  @doc "Seconds to wait before the next attempt, given the attempt number that just failed (1-indexed). `nil` once the five-attempt/one-hour ceiling is reached."
  @spec next_wait_seconds(pos_integer(), DateTime.t(), DateTime.t()) :: pos_integer() | nil
  def next_wait_seconds(attempt, first_attempt_at, now) do
    elapsed = DateTime.diff(now, first_attempt_at, :second)

    cond do
      attempt >= @max_attempts -> nil
      elapsed >= @ceiling_seconds -> nil
      true -> Enum.at(@backoff_seconds, attempt - 1, List.last(@backoff_seconds))
    end
  end

  defp fetch_binary(input, key) do
    case Map.get(input, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing_or_invalid -> {:error, :invalid_shape}
    end
  end

  defp validate_endpoint(endpoint) do
    with :ok <- validate_bounded(endpoint, @max_endpoint_bytes),
         :ok <- validate_no_fragment(endpoint),
         # `userinfo: nil` enforces tech-doc 004's "no user information" rule
         # directly in the pattern match -- `https://user@host/...` parses
         # with a non-nil `userinfo` and is rejected here, before any
         # host/port/allowlist check runs.
         %URI{scheme: "https", host: host, port: port, userinfo: nil} <- URI.parse(endpoint),
         :ok <- validate_not_ip_literal(host),
         :ok <- validate_default_port(port),
         :ok <- validate_allowlisted_host(host) do
      :ok
    else
      _rejected -> {:error, :endpoint_not_allowed}
    end
  end

  defp validate_bounded(value, max_bytes) do
    if byte_size(value) in 1..max_bytes, do: :ok, else: {:error, :too_long}
  end

  defp validate_no_fragment(endpoint) do
    if String.contains?(endpoint, "#"), do: {:error, :fragment_present}, else: :ok
  end

  defp validate_not_ip_literal(host) when is_binary(host) do
    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, _address} -> {:error, :ip_literal}
      {:error, :einval} -> :ok
    end
  end

  defp validate_not_ip_literal(_host), do: {:error, :invalid_host}

  # HTTPS's implied default is 443; anything else (including an explicit
  # ":443") is rejected -- URI.parse/1 already normalizes an explicit ":443"
  # suffix to `port: 443`, so this single check covers both forms.
  defp validate_default_port(443), do: :ok
  defp validate_default_port(_other_port), do: {:error, :nondefault_port}

  # Exact lower-case ASCII match or an explicitly approved suffix with a dot
  # boundary (tech-doc 004) -- never substring containment, so
  # "evilpush.apple.com.example" or a bare suffix without the boundary dot
  # never matches.
  defp validate_allowlisted_host(host) do
    normalized = host |> to_string() |> String.downcase()

    if ascii_only?(normalized) and Enum.any?(allowlisted_hosts(), &host_matches?(normalized, &1)) do
      :ok
    else
      {:error, :host_not_allowed}
    end
  end

  defp host_matches?(host, allowed),
    do: host == allowed or String.ends_with?(host, "." <> allowed)

  defp ascii_only?(value), do: value |> String.to_charlist() |> Enum.all?(&(&1 < 128))

  defp validate_key_shape(value, max_bytes) do
    with :ok <- validate_bounded(value, max_bytes),
         {:ok, _decoded} <- Base.url_decode64(value, padding: false) do
      :ok
    else
      _invalid -> {:error, :invalid_key_shape}
    end
  end
end
