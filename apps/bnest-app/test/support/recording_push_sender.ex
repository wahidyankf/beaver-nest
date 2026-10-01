defmodule BnestApp.Test.RecordingPushSender do
  @moduledoc """
  The test environments' `BnestApp.PushNotifications.Ports.PushSender`, configured in
  `config/test.exs` for the integration layer and the end-to-end servers. It lives under
  `test/support/`, so no release ships it. It never reaches the network: it accepts every
  request as the synthetic provider on `push.allowed.example.com` would, and records it by
  sending
  `{:push_notification_sent, endpoint, payload}` to the calling process (the dispatcher
  sends in its caller's process).

  It names that synthetic host, which the subscription allowlist therefore accepts in the
  test environments, besides the production push services.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @behaviour BnestApp.PushNotifications.Ports.PushSender

  @impl true
  def send(%{endpoint: endpoint}, payload) when is_map(payload) do
    Kernel.send(self(), {:push_notification_sent, endpoint, payload})
    {:status, 201}
  end

  @impl true
  def synthetic_provider_hosts, do: ["push.allowed.example.com"]
end
