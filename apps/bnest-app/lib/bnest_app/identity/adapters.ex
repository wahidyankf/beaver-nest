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
      BnestApp.PushNotifications,
      Argon2
    ],
    exports: :all
end
