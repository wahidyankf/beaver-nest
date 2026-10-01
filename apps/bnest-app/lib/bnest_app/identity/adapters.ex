defmodule BnestApp.Identity.Adapters do
  @moduledoc """
  Identity's outbound adapters: the record-backed identity store, the Argon2id credential
  hasher, the endpoint session notifier, and the push-subscription revoker. Only
  configuration names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [
      BnestApp.Identity,
      BnestApp.Storage,
      BnestAppWeb,
      # legacy: PushSubscriptionRevoker calls BnestApp.PushNotifications; U10 swaps this
      # for the PushNotifications facade.
      BnestApp,
      Argon2
    ],
    exports: :all
end
