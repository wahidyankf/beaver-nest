defmodule BnestApp.Operations.Ports do
  @moduledoc """
  The behaviours the Operations application needs from the outside world: the release
  environment the server runs in. Adapters under `BnestApp.Operations.Adapters` implement
  them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
