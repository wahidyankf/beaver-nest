defmodule BnestApp.Storage.Domain.LocationTest do
  use ExUnit.Case, async: true

  alias BnestApp.Storage.Domain.Location

  defp missing,
    do: %{lstat: fn _path -> {:error, :enoent} end, stat: fn _path -> {:error, :enoent} end}

  test "the default directory follows the storage profile" do
    assert Location.default_directory(:production) == Location.production_data_directory()
    assert Location.production_data_directory() =~ ~r{/bnest/data/prod$}

    assert Location.default_directory({:test, "run-unit"}) ==
             Location.test_data_directory("run-unit")

    assert Location.test_data_directory("run-unit") =~ ~r{/bnest/data/test/runs/run-unit$}
  end

  test "a test profile needs a run identifier" do
    assert_raise ArgumentError, "BNEST_TEST_RUN_ID is required", fn ->
      Location.test_data_directory("")
    end
  end

  test "rejects a directory that is not a path" do
    assert Location.validate(nil, missing()) == {:error, :not_absolute}
  end

  test "accepts a private directory that does not exist yet" do
    assert Location.validate("/srv/bnest-unit/data", missing()) == {:ok, "/srv/bnest-unit/data"}
  end
end
