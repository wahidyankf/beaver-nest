defmodule BnestApp.Test.Contracts do
  @moduledoc """
  Port contract suites. Each `BnestApp.Test.Contracts.*Contract` case template runs one
  port's shared behaviour against any implementation: the in-memory double in the unit layer
  and the real adapter in the integration layer.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
end
