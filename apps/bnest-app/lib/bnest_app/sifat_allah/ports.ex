defmodule BnestApp.SifatAllah.Ports do
  @moduledoc """
  The behaviours the Sifat Allah application needs from the outside world. Adapters under
  `BnestApp.SifatAllah.Adapters` implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.SifatAllah.Domain], exports: :all
end
