ExUnit.start()

# The integration run's end-of-suite audit (ADR 001, section 3). ExUnit runs `after_suite` callbacks in
# reverse registration order, so this one is registered before ExBdd compiles its features: ExBdd's own
# callback (after_all hooks and the message flush) runs first, and this audit runs last. It counts the instance
# directories and the current instance and checks that the run base holds no data at all (see
# `BnestApp.TestInstance.Audit`), then removes the run roots. A failure prints every reason and halts the VM
# with status 1, because a suite callback cannot change the status that Mix reports.
if System.get_env("BNEST_TEST_LAYER") == "integration" and
     Application.get_env(:bnest_app, :test_runtime_owned) do
  runtime_root = Application.fetch_env!(:bnest_app, :runtime_root)
  sqlite_root = Application.fetch_env!(:bnest_app, :test_sqlite_root)

  ExUnit.after_suite(fn _result ->
    verdict =
      BnestApp.TestInstance.Audit.verdict(
        BnestApp.TestInstance.audit().directories,
        BnestApp.TestInstance.state(),
        BnestApp.TestInstance.base_audit()
      )

    _stopped = Application.stop(:bnest_app)
    {:ok, runtime} = BnestApp.TestRuntimeRoot.validate(runtime_root)

    :ok =
      BnestApp.TestRuntimeRoot.cleanup!(%{
        path: runtime_root,
        sqlite_path: sqlite_root,
        run_id: runtime.run_id
      })

    case verdict do
      :ok ->
        :ok

      {:error, reasons} ->
        IO.puts(:stderr, "Test leak audit failed:\n  * " <> Enum.join(reasons, "\n  * "))
        System.halt(1)
    end
  end)
end

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
      {BnestAppWeb.ScenarioCase, Path.join(__DIR__, "behaviour/support/integration.exs"), & &1}

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
