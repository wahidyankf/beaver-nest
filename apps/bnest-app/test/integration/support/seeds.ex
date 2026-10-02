defmodule BnestApp.Test.Seeds do
  @moduledoc """
  Test-only seeding of real SQLite tables for the integration layer and the e2e servers
  (`MIX_ENV=test`). Each `BnestApp.Test.Seeds.*` module writes the rows a scenario's Given
  describes, through SQL the product never runs. Only the test environment compiles them.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
end
