defmodule BnestApp.Test.InMemory.SubscriptionRevoker do
  @moduledoc """
  A recording `BnestApp.Identity.Ports.SubscriptionRevoker`. Logout runs in the caller's
  process, so each revocation is sent to that process as
  `{:subscription_revoked, user_id, session_digest}` for the test to assert.
  """

  @behaviour BnestApp.Identity.Ports.SubscriptionRevoker

  @impl true
  def revoke(user_id, session_digest) do
    send(self(), {:subscription_revoked, user_id, session_digest})
    {:ok, %{enabled: false}}
  end
end
