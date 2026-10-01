defmodule BnestApp.Identity.Ports do
  @moduledoc """
  The behaviours the Identity application needs from the outside world. Adapters under
  `BnestApp.Identity.Adapters` implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.Identity.Domain], exports: :all
end
