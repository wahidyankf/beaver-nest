defmodule BnestApp.PushNotifications.Domain do
  @moduledoc """
  The Push Notifications domain: which subscription input and endpoints are acceptable, the
  payload a family chat delivery sends, and how a provider's answer and the retry schedule
  decide a delivery's next state. Pure: no file, process, clock, database, or network access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
