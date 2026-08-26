ExUnit.start()

behaviour_root = Path.expand("../../../specs/apps/bnest/app/behaviours", __DIR__)

{case_template, support} =
  case System.get_env("BNEST_TEST_LAYER", "unit") do
    "unit" ->
      {ExUnit.Case, Path.join(__DIR__, "behaviour/support/unit.exs")}

    "integration" ->
      {BnestAppWeb.ConnCase, Path.join(__DIR__, "behaviour/support/integration.exs")}

    layer ->
      raise "BNEST_TEST_LAYER must be unit or integration, got: #{inspect(layer)}"
  end

ExBdd.compile_features!(
  features: [Path.join(behaviour_root, "**/*.feature")],
  steps: [Path.join(__DIR__, "behaviour/steps/**/*.exs")],
  support: [support],
  case_template: case_template
)

if System.get_env("BNEST_TEST_LAYER") == "integration" and
     Application.get_env(:bnest_app, :test_runtime_owned) do
  runtime_root = Application.fetch_env!(:bnest_app, :runtime_root)

  ExUnit.after_suite(fn _result ->
    _stopped = Application.stop(:bnest_app)
    {:ok, runtime} = BnestApp.TestRuntimeRoot.validate(runtime_root)
    :ok = BnestApp.TestRuntimeRoot.cleanup!(runtime)
  end)
end
