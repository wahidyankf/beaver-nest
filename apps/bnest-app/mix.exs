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
      {:bandit, "~> 1.5"},
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.19"},
      {:absinthe, "~> 1.12"},
      {:absinthe_plug, "~> 1.5.10"},
      {:absinthe_phoenix, "~> 2.0.5"},
      # RFC 8291 payload encryption + RFC 8292 VAPID signing (tech-doc 004).
      # Re-verified at Phase 5 against Phase 0's dependency-selection review:
      # still hex.pm's only actively-maintained Web Push protocol library
      # (`web_push_encryption` is abandoned), still 0.1.0/MIT as of this
      # check. Only its `WebPush.Vapid`/`WebPush.Encryption` building blocks
      # are used (see `BnestApp.PushNotifications.Sender`); the actual HTTP
      # POST goes through `Req` (already a dependency) so this delivery's own
      # redirect-disabled, bounded-timeout policy applies uniformly rather
      # than depending on `WebPush.send/3`'s internal Finch pool config.
      {:web_push, "~> 0.1.0"}
    ]
  end

  defp test_coverage do
    generated_or_static = [
      BnestAppWeb.CoreComponents,
      BnestAppWeb.Endpoint,
      BnestAppWeb.Telemetry,
      BnestApp.Codex.PortSession,
      BnestAppWeb.ErrorHTML,
      BnestAppWeb.Gettext,
      BnestAppWeb.Layouts,
      BnestAppWeb.PageController,
      BnestAppWeb.PageHTML,
      BnestAppWeb.ReleaseHeaders,
      BnestAppWeb.Router,
      BnestAppWeb.FamilyChatHTML
    ]

    test_scaffolding = [
      BnestApp.Behaviour.BoundaryPolicy,
      BnestApp.Behaviour.Driver,
      BnestApp.Behaviour.IntegrationFamilyChatDriver,
      BnestApp.Behaviour.IntegrationHomePageDriver,
      BnestApp.Behaviour.MemoryBackend,
      BnestApp.Behaviour.UnitFamilyChatDriver,
      BnestApp.Behaviour.UnitHomePageDriver,
      BnestApp.Codex.FixtureModels,
      BnestApp.Codex.FixtureSession,
      BnestApp.SchemaSourceScan,
      BnestApp.TestIdentity,
      BnestApp.TestRuntimeRoot,
      BnestAppWeb.ConnCase
    ]

    boundary_adapters = [
      BnestApp.AdminConfig.Registry,
      BnestApp.Application,
      BnestApp.Codex.ModelDiscovery,
      BnestApp.Backup,
      BnestApp.Backup.Capacity,
      BnestApp.Backup.Config,
      BnestApp.Backup.Location,
      BnestApp.Backup.Receipt,
      BnestApp.Backup.Run,
      BnestApp.DataRepository.Backup,
      BnestApp.DataRepository.Import,
      BnestApp.DataRepository.Manifest,
      BnestApp.DataRepository.RecoverySource,
      BnestApp.DataRepository.Schema,
      BnestApp.DataRepository.SqliteStore,
      BnestApp.DataRepository.Store,
      BnestApp.DataRepository.StorageCoordinator,
      BnestApp.Deployment,
      BnestApp.Identity,
      BnestApp.Identity.Bootstrap,
      BnestApp.Identity.CredentialVerifier,
      BnestApp.Identity.FileStore,
      BnestApp.FamilyChat.Store,
      BnestApp.Identity.Session,
      BnestApp.PushNotifications,
      BnestApp.PushNotifications.Dispatcher,
      BnestApp.PushNotifications.RetentionJob,
      BnestApp.PushNotifications.Sender,
      BnestApp.Release.Migrations.FamilyChat,
      BnestApp.Release.Migrations.PersistentSchedules,
      BnestApp.Scheduler,
      BnestApp.Scheduler.Registry,
      BnestApp.Scheduler.Run,
      BnestApp.Scheduler.Store,
      BnestApp.SqliteRepo,
      BnestApp.Storage.Config,
      BnestApp.Storage.Location,
      BnestApp.Storage.Lock,
      BnestApp.Storage.Migration,
      BnestApp.Storage.RecordMap,
      BnestApp.Storage.Relocation,
      BnestApp.Storage.Retirement,
      BnestApp.Storage.TestDataCleanup,
      BnestAppWeb.BootstrapController,
      BnestAppWeb.AdminScheduleSettingsLive,
      BnestAppWeb.AdminSettingsLive,
      BnestAppWeb.ChatLive,
      BnestAppWeb.DataMigrationLive,
      BnestAppWeb.FamilyChatController,
      BnestAppWeb.HealthController,
      BnestAppWeb.LoginLive,
      BnestAppWeb.Plugs.GraphQLPipeline,
      BnestAppWeb.SessionController,
      BnestAppWeb.SifatAllahLive,
      BnestAppWeb.StorageLive,
      BnestAppWeb.ThemeController,
      BnestAppWeb.UserAuth,
      BnestAppWeb.Schema,
      BnestAppWeb.Schema.Types.FamilyChatTypes,
      BnestAppWeb.Schema.Types.WebPushTypes,
      BnestAppWeb.Resolvers.FamilyChatResolver,
      BnestAppWeb.Resolvers.WebPushResolver,
      BnestAppWeb.UserSocket,
      Mix.Tasks.Bnest.Identity.Benchmark,
      Mix.Tasks.Bnest.Schema.Audit,
      Mix.Tasks.Bnest.Storage.Migrate,
      Mix.Tasks.Bnest.Storage.Relocate,
      Mix.Tasks.Bnest.Storage.Retire,
      Mix.Tasks.Bnest.Storage.PurgeTestData
    ]

    # Only the unit layer carries a coverage threshold. `test:integration` still exercises
    # the boundary adapters, but its result is a pass or fail, not a measured denominator.
    [
      output: "cover/unit",
      summary: [threshold: 99],
      ignore_modules: generated_or_static ++ test_scaffolding ++ boundary_adapters
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
