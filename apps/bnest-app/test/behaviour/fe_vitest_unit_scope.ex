defmodule BnestApp.Behaviour.FeVitestUnitScope do
  @moduledoc """
  Prunes `@fe-vitest-unit` scenarios from a discovered feature corpus before
  Elixir ExBdd compiles or verifies it.

  `family_chat.feature` scenarios covering the IndexedDB outbox, retry
  backoff, reconnect/reconcile, push-permission UI, and scroll/accessibility
  concerns are genuinely not observable from Elixir (see tech-doc 006's Proof
  Matrix: "Not applicable"/"Not layout-capable" for the combined BE
  unit/integration column). They are proven instead by the frontend
  Vitest+Gherkin harness at `apps/bnest-app/assets/test/behaviour/verify.ts`,
  which requires exactly the complementary `@fe-vitest-unit` scenario set.

  `ExBdd.Verifier`/`ExBdd.Compiler` have no scenario- or tag-level exclusion
  of their own (confirmed by reading `ExBdd.Discovery.discover/1`, whose
  `:features` option is a file glob, and `ExBdd.Verifier.verify!/1`, which
  requires every discovered pickle to bind); they only offer file-granularity
  scoping. Rather than fork the shared `libs/ex-bdd` engine (out of this
  plan's scope) or split the canonical `family_chat.feature` file (deviating
  from the File Impact list), this module prunes `@fe-vitest-unit`-tagged
  scenarios from every discovered feature's `scenarios` and `rules[].
  scenarios` lists before the `DiscoveryResult` reaches `ExBdd.Verifier.
  verify!/1` (via `test/behaviour/verify.exs`) or `ExBdd.Compiler.
  compile_discovery!/2` (via `test/test_helper.exs`). Both call sites apply
  this same prune, for both the `unit:` and `integration:` adapters, since
  the Proof Matrix marks both columns not applicable together.

  This module lives directly under `test/behaviour/` (not `test/behaviour/
  support/`, which only holds ex_bdd hook/support files ex_bdd itself
  loads by glob) specifically so plain `mix compile` picks it up via
  `elixirc_paths(:test)` and it is available to both `mix run
  test/behaviour/verify.exs` and `mix test` (which loads `test_helper.exs`)
  without either file needing to `Code.require_file` it.
  """

  alias ExBdd.Discovery.DiscoveryResult

  @tag "fe-vitest-unit"

  @spec prune(DiscoveryResult.t()) :: DiscoveryResult.t()
  def prune(%DiscoveryResult{} = discovery) do
    Map.update!(discovery, :features, fn features -> Enum.map(features, &prune_feature/1) end)
  end

  defp prune_feature(feature) do
    feature
    |> Map.update!(:scenarios, &reject_tagged/1)
    |> Map.update!(:rules, fn rules -> Enum.map(rules, &prune_rule/1) end)
  end

  defp prune_rule(rule), do: Map.update!(rule, :scenarios, &reject_tagged/1)

  defp reject_tagged(scenarios), do: Enum.reject(scenarios, &(@tag in &1.tags))
end
