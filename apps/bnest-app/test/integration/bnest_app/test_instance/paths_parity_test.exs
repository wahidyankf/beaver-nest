defmodule BnestApp.TestInstance.PathsParityTest do
  # The shared parity fixture is read by the TypeScript path mirrors and by this test. Every case
  # must derive exactly the expected paths, or exactly the expected error, from `Paths.derive/4`.
  use ExUnit.Case, async: true

  @moduletag :test_instance

  alias BnestApp.TestInstance.Paths

  @fixture Path.expand("../../../fixtures/test_instance_paths.json", __DIR__)
  @external_resource @fixture

  test "every parity fixture case derives the expected paths or error" do
    cases = @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")

    # An empty fixture would pass every comparison below, so it is refused explicitly.
    refute cases == []

    mismatches =
      for fixture_case <- cases,
          derive(fixture_case) != expected(fixture_case),
          do: {fixture_case["name"], derive(fixture_case), expected(fixture_case)}

    assert mismatches == []
  end

  defp derive(%{"input" => input}) do
    Paths.derive(
      input["flatRunRoot"],
      input["sqliteRunRoot"],
      input["runId"],
      input["instanceId"]
    )
  end

  defp expected(%{"expect" => %{"ok" => true, "paths" => paths}}) do
    {:ok, Map.new(paths, fn {key, value} -> {snake_case_key(key), value} end)}
  end

  defp expected(%{"expect" => %{"ok" => false, "error" => error}}) do
    {:error, String.to_atom(error)}
  end

  # The fixture names keys in camelCase (`sqliteInstanceRoot`); `Paths` uses snake_case atoms.
  defp snake_case_key(key), do: key |> Macro.underscore() |> String.to_atom()
end
