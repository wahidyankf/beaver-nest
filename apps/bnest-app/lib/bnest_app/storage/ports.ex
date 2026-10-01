defmodule BnestApp.Storage.Ports do
  @moduledoc """
  The behaviours the Storage application needs from the outside world. Adapters under
  `BnestApp.Storage.Adapters` implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.Storage.Domain], exports: :all
end
