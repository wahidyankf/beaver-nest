defmodule BnestApp.PushNotifications.Ports.PushSender do
  @moduledoc """
  The push client: sends one family chat payload to a subscription's endpoint. The
  dispatcher is its only caller.

  `send/2` never raises for a provider or network failure; it returns the outcome, which
  `BnestApp.PushNotifications.Domain.Policy.classify_result/1` turns into the delivery's
  next state.

  `synthetic_provider_hosts/0` names the hosts of synthetic providers the sender answers
  for without the network. The subscription allowlist accepts them besides the production
  push services, so only a sender that never dials out may name any; one that reaches the
  network returns `[]`.
  """

  @type subscription :: %{endpoint: String.t(), p256dh: String.t(), auth: String.t()}
  @type outcome :: {:status, non_neg_integer()} | {:transport, atom()}

  @callback send(subscription(), payload :: map()) :: outcome()
  @callback synthetic_provider_hosts() :: [String.t()]
end
