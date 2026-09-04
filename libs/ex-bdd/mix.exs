defmodule ExBdd.MixProject do
  use Mix.Project

  @version "1.0.0"
  @description "Beaver Nest's independently maintained Gherkin BDD engine for Elixir"

  def project do
    [
      app: :ex_bdd,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: @description,
      test_coverage: test_coverage(),
      # Step and support files are loaded by ExBdd discovery, not ExUnit.
      test_ignore_filters: [
        ~r/features\/step_definitions/,
        ~r/features\/support/
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_coverage do
    test_scaffolding = [
      ~r/^ExBdd\.BehaviorCase/,
      ~r/^ExBdd\.CckApproval/,
      ExBdd.ReloadableHooks
    ]

    integration_owned = [
      ExBdd,
      ExBdd.BeforeAllError,
      ExBdd.Compiler,
      ExBdd.Discovery,
      ExBdd.Gherkin.Markdown,
      ExBdd.Gherkin.NimbleParser,
      ExBdd.Gherkin.ParseError,
      ExBdd.Gherkin.Parser,
      ExBdd.Hooks,
      ExBdd.Messages,
      ExBdd.Messages.Emitter,
      ExBdd.ParameterTypes,
      ExBdd.PendingStepError,
      ExBdd.RunCoordinator,
      ExBdd.Runtime,
      ExBdd.VerificationError,
      ExBdd.Verifier
    ]

    unit_owned = [
      ExBdd.Expression,
      ExBdd.Gherkin.NimbleParser,
      ExBdd.Gherkin.Pickles,
      ExBdd.Hooks,
      ExBdd.Messages,
      ExBdd.Runtime,
      ExBdd.StepError,
      ExBdd.UndefinedParameterTypeError
    ]

    {output, layer_exclusions} =
      case System.get_env("EX_BDD_TEST_LAYER") do
        "unit" -> {"cover/unit", integration_owned}
        "integration" -> {"cover/integration", unit_owned}
        "engine" -> {"cover/engine", []}
        _other -> {"cover", []}
      end

    [
      output: output,
      summary: [threshold: 99],
      ignore_modules: test_scaffolding ++ layer_exclusions
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "format",
        "credo --strict",
        "deps.unlock --unused",
        "test"
      ]
    ]
  end
end
