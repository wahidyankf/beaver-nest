defmodule BnestApp.CodexChat.Ports do
  @moduledoc """
  The behaviours the Codex chat application needs from the outside world. Adapters under
  `BnestApp.CodexChat.Adapters` implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.CodexChat.Domain], exports: :all
end
