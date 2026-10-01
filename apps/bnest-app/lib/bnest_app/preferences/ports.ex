defmodule BnestApp.Preferences.Ports do
  @moduledoc """
  The behaviours the Preferences application needs from the outside world. Adapters under
  `BnestApp.Preferences.Adapters` implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.Preferences.Domain], exports: :all
end
