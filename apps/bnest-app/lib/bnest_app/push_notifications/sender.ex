defmodule BnestApp.PushNotifications.Sender do
  @moduledoc """
  The one place that performs Web Push egress (tech-doc 004: "egress only in
  the dispatcher"). Encrypts the payload with `WebPush.Encryption` (RFC 8291)
  and signs the VAPID `Authorization` header with `WebPush.Vapid` (RFC 8292),
  then POSTs the encrypted body with `Req` directly rather than
  `WebPush.send/3`'s own Finch transport -- this module owns the exact
  redirect-disabled, bounded-timeout policy tech-doc 004 requires
  (`redirect: false`, explicit connect/receive timeouts) instead of depending
  on an unconfigured Finch pool's defaults.
  """

  alias WebPush.Encryption
  alias WebPush.Vapid

  @connect_timeout_ms 5_000
  @receive_timeout_ms 10_000

  @type outcome :: {:status, non_neg_integer()} | {:transport, atom()}

  @doc """
  Sends one encrypted push request to `subscription`'s endpoint. Never raises
  for a network/provider failure -- every outcome is a plain classified
  return value the dispatcher transitions the delivery row from.
  """
  @spec send(map(), map()) :: outcome()
  def send(%{endpoint: endpoint, p256dh: p256dh, auth: auth}, payload) when is_map(payload) do
    case encrypt(payload, p256dh, auth) do
      {:ok, body} -> post(endpoint, body)
      :error -> {:transport, :corrupt_subscription}
    end
  end

  # `WebPush.Encryption.encrypt_with/5` deliberately raises (its own "Sanity:
  # wrong sizes here mean a corrupt subscription" check) rather than
  # returning an error tuple for malformed key material -- a stored
  # `p256dh`/`auth` that is not validly base64url or not RFC 8291's expected
  # byte length. This module's own moduledoc promises the dispatcher a plain
  # classified outcome, never a raise, so a corrupt row is caught here and
  # classified like any other unreachable-provider failure (`:transport`,
  # which `Policy.classify_result/1` already maps to `:retryable` -- the
  # existing retry-ceiling/lease-recovery machinery bounds it exactly like
  # any other persistently-failing delivery) instead of crashing the
  # Scheduler's dispatch task.
  defp encrypt(payload, p256dh, auth) do
    {:ok, payload |> Jason.encode!() |> Encryption.encrypt(p256dh, auth)}
  rescue
    _corrupt_key_material -> :error
  end

  defp post(endpoint, body) do
    endpoint
    |> Req.post(
      headers: [
        {"authorization", Vapid.authorization_header(endpoint)},
        {"content-type", "application/octet-stream"},
        {"content-encoding", "aes128gcm"},
        {"ttl", "86400"}
      ],
      body: body,
      # Tech-doc 004: "any 3xx is terminal and its location is never
      # requested" -- `redirect: false` is explicit defense-in-depth even
      # though Req/Finch never auto-follow without opting in.
      redirect: false,
      connect_options: [timeout: @connect_timeout_ms],
      receive_timeout: @receive_timeout_ms,
      retry: false
    )
    |> classify()
  end

  defp classify({:ok, %Req.Response{status: status}}), do: {:status, status}

  defp classify({:error, %{reason: reason}}) when is_atom(reason), do: {:transport, reason}
  defp classify({:error, _other}), do: {:transport, :unknown}
end
