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
      test_coverage: [
        summary: [threshold: 99],
        ignore_modules: [
          ~r/^ExBdd\.BehaviorCase/,
          ~r/^ExBdd\.CckApproval/,
          ExBdd.ReloadableHooks
        ]
      ],
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
