defmodule BnestApp.Identity.Ports.SubscriptionRevoker do
  @moduledoc """
  Deactivates the push subscription a browser session registered, before that session is
  revoked. A failure raises, so logout stops before revocation and the user can retry.
  """

  @callback revoke(user_id :: String.t(), session_digest :: String.t()) :: term()
end
