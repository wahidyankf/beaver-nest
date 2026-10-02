# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bnest_app,
  generators: [timestamp_type: :utc_datetime],
  storage_profile: :production,
  runtime_root: Path.expand("../../../data/prod", __DIR__),
  identity_cutover_enabled: false,
  family_chat_enabled: false,
  family_chat_reply_enabled: false,
  backup_timeout_ms: 1_800_000,
  session_cookie: [
    key: "_bnest_identity",
    secure: false,
    same_site: "Lax",
    max_age: 60 * 60 * 24 * 365 * 20
  ],
  argon2: [memory_kib: 32_768, time_cost: 2, parallelism: 1],
  codex: [
    working_directory: Path.expand("../../..", __DIR__)
  ]

# Configure the endpoint
config :bnest_app, BnestAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BnestAppWeb.ErrorHTML, json: BnestAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BnestApp.PubSub,
  live_view: [signing_salt: "hErpnfVP"]

config :argon2_elixir,
  argon2_type: 2,
  m_cost: 15,
  t_cost: 2,
  parallelism: 1

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :bnest_app, BnestApp.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bnest_app: [
    # --external:node:fs / node:url / happy-dom: `family_chat/accessibility.js`
    # reads the shipped stylesheet from disk and renders a probe list into a
    # DOM of its own, but only from FE_UNIT's Vitest (Node) process --
    # `family_chat.js`'s browser path never calls it (see its own
    # `hasDocument` guard). All three are therefore legitimately never
    # resolvable (or needed) in this browser bundle; marking them external
    # leaves the dead import as an inert, never-executed reference instead of
    # a bundle failure -- and keeps a whole DOM implementation out of what
    # every visitor downloads.
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --external:node:fs --external:node:url --external:happy-dom --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  version_check: false,
  path: Path.expand("../../../node_modules/.bin/tailwindcss", __DIR__),
  bnest_app: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.

config :bnest_app, BnestApp.SqliteRepo,
  pool_size: 5,
  # SqliteCoordinator establishes WAL once before the pool starts so pooled
  # connections do not race on the database-wide journal transition.
  journal_mode: nil,
  busy_timeout: 5_000,
  foreign_keys: :on,
  synchronous: :full,
  priv: "priv/sqlite_repo",
  # Query logs would otherwise print full record payloads (chat, learning
  # progress, account details) to stdout/log files. Keep storage operations
  # as value-free as the flat-file Store adapter they replace.
  log: false

config :bnest_app, ecto_repos: [BnestApp.SqliteRepo]

# One adapter per Storage port, plus the record kinds other contexts register.
config :bnest_app, BnestApp.Storage,
  config_store: BnestApp.Storage.Adapters.FileConfigStore,
  lock: BnestApp.Storage.Adapters.FileLock,
  database_lifecycle: BnestApp.Storage.Adapters.SqliteCoordinator,
  maintenance: BnestApp.Storage.Adapters.LocalMaintenance,
  record_kinds: [
    BnestApp.CodexChat.Adapters.TranscriptRecordKind,
    BnestApp.SifatAllah.Adapters.ProgressRecordKind
  ]

# One adapter per Identity port.
config :bnest_app, BnestApp.Identity,
  identity_store: BnestApp.Identity.Adapters.RecordIdentityStore,
  credential_hasher: BnestApp.Identity.Adapters.Argon2CredentialHasher,
  session_notifier: BnestApp.Identity.Adapters.EndpointSessionNotifier,
  subscription_revoker: BnestApp.Identity.Adapters.PushSubscriptionRevoker

# One adapter per Preferences port.
config :bnest_app, BnestApp.Preferences,
  preference_store: BnestApp.Preferences.Adapters.RecordPreferenceStore

# One adapter per Sifat Allah port.
config :bnest_app, BnestApp.SifatAllah,
  progress_store: BnestApp.SifatAllah.Adapters.RecordProgressStore

# One adapter per Codex chat port.
config :bnest_app, BnestApp.CodexChat,
  agent_session: BnestApp.CodexChat.Adapters.CodexPortSession,
  model_discovery: BnestApp.CodexChat.Adapters.CodexCliModelDiscovery,
  transcript_store: BnestApp.CodexChat.Adapters.RecordTranscriptStore

# One adapter per Family Chat port.
config :bnest_app, BnestApp.FamilyChat,
  room_store: BnestApp.FamilyChat.Adapters.SqliteRoomStore,
  message_publisher: BnestApp.FamilyChat.Adapters.AbsintheMessagePublisher

# One adapter per Push Notifications port. The Web Push sender's allowlist names only the
# production push services.
config :bnest_app, BnestApp.PushNotifications,
  subscription_store: BnestApp.PushNotifications.Adapters.SqliteSubscriptionStore,
  delivery_store: BnestApp.PushNotifications.Adapters.SqliteDeliveryStore,
  push_sender: BnestApp.PushNotifications.Adapters.WebPushSender

# The Scheduler's schedule store, the task registered under each handler key a schedule row
# stores, and the handlers every regular tick runs. The Scheduler names no other context:
# Backup and Push Notifications reach it through these task adapters and tick handlers.
# A running task renews its lease every `lease_renewal_interval_ms`, well inside the lease
# `BnestApp.Scheduler.Domain.Policy.lease_until/1` grants.
config :bnest_app, BnestApp.Scheduler,
  schedule_store: BnestApp.Scheduler.Adapters.SqliteScheduleStore,
  tasks: %{
    "prod_sqlite_backup" => %{
      label: "Production database backup",
      context: "admin_system",
      handler: BnestApp.Backup.Run,
      settings_key: "schedules-backups",
      timezone: "WIB (UTC+07:00)"
    },
    "family_chat_push_retention" => %{
      label: "Family chat push delivery retention",
      context: "admin_system",
      handler: BnestApp.PushNotifications.Adapters.RetentionTask,
      settings_key: nil,
      timezone: "WIB (UTC+07:00)"
    },
    "fixture" => %{
      label: "Family fixture",
      context: "family",
      handler: BnestApp.Scheduler.TaskRegistry,
      settings_key: nil,
      timezone: "WIB (UTC+07:00)"
    }
  },
  tick_handlers: [{BnestApp.PushNotifications, :dispatch_all_due!, []}],
  lease_renewal_interval_ms: 60_000

import_config "#{config_env()}.exs"
