defmodule BnestApp.HexagonalLayeringTest do
  use ExUnit.Case, async: true

  alias BnestApp.ArchitectureScan

  test "every core module sits in a context whose layers keep effects, purity and facades" do
    violations = ArchitectureScan.violations()

    assert violations == [], ArchitectureScan.format(violations)
  end
end
