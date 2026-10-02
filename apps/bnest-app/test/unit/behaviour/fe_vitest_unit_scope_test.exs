defmodule BnestApp.Behaviour.FeVitestUnitScopeTest do
  @moduledoc """
  The prune that hands `@fe-vitest-unit` scenarios to the Vitest harness drops them from
  the integration layer too, so it only does so for a scenario that records why
  integration does not bind it.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.FeVitestUnitScope
  alias ExBdd.Discovery.DiscoveryResult
  alias ExBdd.Gherkin.Parser

  defp discovery(feature_source),
    do: %DiscoveryResult{features: [Parser.parse(feature_source)]}

  defp scenario_names(%DiscoveryResult{features: features}) do
    Enum.flat_map(features, fn feature ->
      Enum.map(feature.scenarios ++ Enum.flat_map(feature.rules, & &1.scenarios), & &1.name)
    end)
  end

  test "drops an exempted @fe-vitest-unit scenario and keeps the rest" do
    pruned =
      FeVitestUnitScope.prune(
        discovery("""
        Feature: Scope

          Rule: Room

          Scenario: Server rendered
            When a visitor opens "/"

          @fe-vitest-unit
          # Exemption(integration): browser JS; alternative-proof: bnest-app:test:unit:fe / Browser only
          @integration-exempt
          Scenario: Browser only
            When a visitor opens "/"
        """)
      )

    assert scenario_names(pruned) == ["Server rendered"]
  end

  test "refuses to drop an @fe-vitest-unit scenario integration does not record as exempt" do
    error =
      assert_raise ArgumentError, fn ->
        FeVitestUnitScope.prune(
          discovery("""
          Feature: Scope

            Rule: Room

            @fe-vitest-unit
            @e2e-exempt
            Scenario: Silently unbound
              When a visitor opens "/"
          """)
        )
      end

    assert error.message =~ "Silently unbound"
    assert error.message =~ "@integration-exempt"
  end
end
