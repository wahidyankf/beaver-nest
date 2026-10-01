defmodule BnestApp.Identity.Adapters.PushSubscriptionRevoker do
  @moduledoc """
  The `BnestApp.Identity.Ports.SubscriptionRevoker` over Web Push. It is the only Identity
  module that names `BnestApp.PushNotifications`.
  """

  @behaviour BnestApp.Identity.Ports.SubscriptionRevoker

  # Tech-doc 002: "Logout completes server deactivation before identity revocation. If
  # deactivation fails, the authenticated session remains so the user can retry; partial
  # logout is not reported as success." An error raised here (e.g. an unavailable database)
  # propagates out of `BnestApp.Identity.logout/1` before the session is revoked, so the
  # session stays valid for a retry rather than being revoked ahead of a failed deactivation.
  @impl true
  def revoke(user_id, session_digest),
    do: BnestApp.PushNotifications.disable_subscription(user_id, session_digest)
end
