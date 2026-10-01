defmodule BnestApp.Test.InMemory.PushSender do
  @moduledoc """
  A push-client double for `BnestApp.PushNotifications.Ports.PushSender`. It reaches no
  network: it answers as a synthetic provider on `push.allowed.example.com` would. An
  endpoint whose last path segment is `status-<code>` is answered with that HTTP status;
  any other is accepted (201).

  The dispatcher sends in the caller's process, so each request is sent to that process as
  `{:push_notification_sent, endpoint, payload}` for the test to assert.
  """

  @behaviour BnestApp.PushNotifications.Ports.PushSender

  @impl true
  def send(%{endpoint: endpoint}, payload) when is_map(payload) do
    Kernel.send(self(), {:push_notification_sent, endpoint, payload})
    answer(endpoint |> String.split("/") |> List.last())
  end

  @impl true
  def synthetic_provider_hosts, do: ["push.allowed.example.com"]

  @doc """
  Drops every request recorded in the calling process so far, so a retried scenario starts
  with none left over from its failed attempt.
  """
  @spec forget_sent() :: :ok
  def forget_sent do
    receive do
      {:push_notification_sent, _endpoint, _payload} -> forget_sent()
    after
      0 -> :ok
    end
  end

  defp answer("status-" <> code), do: {:status, String.to_integer(code)}
  defp answer(_accepted), do: {:status, 201}
end
