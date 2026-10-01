defmodule BnestApp.Test.InMemory do
  @moduledoc """
  In-memory port implementations for the unit layer. Each `BnestApp.Test.InMemory.*` module
  implements one port without touching a disk, a database, or the network, and passes that
  port's contract suite.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
end
