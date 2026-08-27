defmodule BnestApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :bnest_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [
        ~r/test\/behaviour\/steps/,
        ~r/test\/behaviour\/support/
      ],
      test_coverage: test_coverage(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix]],
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BnestApp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test) do
    [
      "lib",
      "test/support",
      "test/behaviour",
      "test/unit/support",
      "test/integration/support"
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:argon2_elixir, "~> 4.1.3"},
      {:ex_bdd, path: "../../libs/ex-bdd", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  defp test_coverage do
    generated_or_static = [
      BnestAppWeb.CoreComponents,
      BnestApp.Codex.PortSession,
      BnestAppWeb.ErrorHTML,
      BnestAppWeb.Gettext,
      BnestAppWeb.Layouts,
      BnestAppWeb.PageController,
      BnestAppWeb.PageHTML,
      BnestAppWeb.ReleaseHeaders,
      BnestAppWeb.Router
    ]

    test_scaffolding = [
      BnestApp.Behaviour.BoundaryPolicy,
      BnestApp.Behaviour.Driver,
      BnestApp.Behaviour.IntegrationHomePageDriver,
      BnestApp.Behaviour.UnitHomePageDriver,
      BnestApp.Codex.FixtureModels,
      BnestApp.Codex.FixtureSession,
      BnestApp.TestIdentity,
      BnestApp.TestRuntimeRoot,
      BnestAppWeb.ConnCase
    ]

    boundary_adapters = [
      BnestApp.Application,
      BnestApp.DataRepository.Backup,
      BnestApp.DataRepository.Import,
      BnestApp.DataRepository.Manifest,
      BnestApp.DataRepository.RecoverySource,
      BnestApp.DataRepository.Schema,
      BnestApp.DataRepository.Store,
      BnestApp.Deployment,
      BnestApp.Identity.Bootstrap,
      BnestApp.Identity.CredentialVerifier,
      BnestApp.Identity.FileStore,
      BnestApp.Identity.Session,
      BnestAppWeb.BootstrapController,
      BnestAppWeb.ChatLive,
      BnestAppWeb.DataMigrationLive,
      BnestAppWeb.HealthController,
      BnestAppWeb.LoginLive,
      BnestAppWeb.SessionController,
      BnestAppWeb.SifatAllahLive,
      BnestAppWeb.ThemeController,
      BnestAppWeb.UserAuth,
      Mix.Tasks.Bnest.Identity.Benchmark,
      Mix.Tasks.Bnest.Schema.Audit
    ]

    {output, layer_exclusions} =
      case System.get_env("BNEST_TEST_LAYER") do
        "unit" ->
          {"cover/unit",
           [
             BnestApp.DataRepository,
             BnestApp.DataRepository.Import,
             BnestApp.Identity,
             BnestApp.Identity.Bootstrap,
             BnestApp.Codex.ModelCatalog,
             BnestAppWeb.Endpoint,
             BnestAppWeb.Telemetry
           ]}

        "integration" ->
          {"cover/integration",
           [
             BnestApp.Chat,
             BnestApp.Codex.ModelAccess,
             BnestApp.DataRepository.Normalizer,
             BnestApp.DataRepository.Schema,
             BnestApp.Identity.Authorization,
             BnestApp.SifatAllah,
             BnestAppWeb.ErrorJSON
           ]}

        _other ->
          {"cover", []}
      end

    [
      output: output,
      summary: [threshold: 99],
      ignore_modules:
        generated_or_static ++ test_scaffolding ++ boundary_adapters ++ layer_exclusions
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind bnest_app", "esbuild bnest_app"],
      "assets.deploy": [
        "tailwind bnest_app --minify",
        "esbuild bnest_app --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
