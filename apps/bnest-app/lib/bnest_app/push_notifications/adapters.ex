defmodule BnestApp.PushNotifications.Adapters do
  @moduledoc """
  Push Notifications' adapters: the subscription and delivery stores over Family Chat's
  SQLite database, the Web Push sender and the test environments' recording sender
  (outbound), and the Scheduler's retention task (inbound). Only configuration names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [
      BnestApp.PushNotifications,
      BnestApp.Scheduler,
      BnestApp.SqliteRepo,
      Jason,
      Req,
      WebPush
    ],
    exports: :all
end
