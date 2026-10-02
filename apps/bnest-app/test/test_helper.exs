ExUnit.start()

behaviour_roots = [
  Path.expand("../../../specs/apps/bnest/app-be/behaviours", __DIR__),
  Path.expand("../../../specs/apps/bnest/app-fe/behaviours", __DIR__)
]

# `@vitest-unit` scenarios' unit layer is the Vitest harness too; their integration layer
# stays here (see `BnestApp.Behaviour.FeVitestUnitScope.prune_unit_layer/1`).
{case_template, support, layer_scope} =
  case System.get_env("BNEST_TEST_LAYER", "unit") do
    "unit" ->
      {ExUnit.Case, Path.join(__DIR__, "behaviour/support/unit.exs"),
       &BnestApp.Behaviour.FeVitestUnitScope.prune_unit_layer/1}

    "integration" ->
      {BnestAppWeb.ConnCase, Path.join(__DIR__, "behaviour/support/integration.exs"), & &1}

    layer ->
      raise "BNEST_TEST_LAYER must be unit or integration, got: #{inspect(layer)}"
  end

# `family_chat.feature`'s `@fe-vitest-unit` scenarios are proven by the
# frontend Vitest+Gherkin harness instead of Elixir ExBdd; see
# `BnestApp.Behaviour.FeVitestUnitScope`'s moduledoc for why this prune
# happens here (compile_features!'s own internal path) rather than via a
# `:features` glob or an ExBdd-native exemption tag.
[
  features: Enum.map(behaviour_roots, &Path.join(&1, "**/*.feature")),
  steps: [Path.join(__DIR__, "behaviour/steps/**/*.exs")],
  support: [support]
]
|> ExBdd.Discovery.discover()
|> BnestApp.Behaviour.FeVitestUnitScope.prune()
|> layer_scope.()
|> ExBdd.Compiler.compile_discovery!(case_template: case_template)

if System.get_env("BNEST_TEST_LAYER") == "integration" and
     Application.get_env(:bnest_app, :test_runtime_owned) do
  runtime_root = Application.fetch_env!(:bnest_app, :runtime_root)
  sqlite_root = Application.fetch_env!(:bnest_app, :test_sqlite_root)

  ExUnit.after_suite(fn _result ->
    _stopped = Application.stop(:bnest_app)
    {:ok, runtime} = BnestApp.TestRuntimeRoot.validate(runtime_root)

    :ok =
      BnestApp.TestRuntimeRoot.cleanup!(%{
        path: runtime_root,
        sqlite_path: sqlite_root,
        run_id: runtime.run_id
      })
  end)
end
