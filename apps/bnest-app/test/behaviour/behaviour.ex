defmodule BnestApp.Behaviour do
  @moduledoc false
  # Test support: every `BnestApp.Behaviour.*` driver reaches internals by design.
  use Boundary, top_level?: true, check: [in: false, out: false]
end
