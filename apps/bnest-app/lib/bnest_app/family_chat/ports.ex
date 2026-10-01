defmodule BnestApp.FamilyChat.Ports do
  @moduledoc """
  The behaviours the Family Chat application needs from the outside world. Adapters under
  `BnestApp.FamilyChat.Adapters` implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.FamilyChat.Domain], exports: :all
end
