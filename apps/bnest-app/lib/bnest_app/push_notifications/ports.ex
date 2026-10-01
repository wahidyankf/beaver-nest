defmodule BnestApp.PushNotifications.Ports do
  @moduledoc """
  The behaviours the Push Notifications application needs from the outside world. Adapters
  under `BnestApp.PushNotifications.Adapters` implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.PushNotifications.Domain], exports: :all
end
