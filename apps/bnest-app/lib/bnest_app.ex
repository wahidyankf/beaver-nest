defmodule BnestApp do
  @moduledoc """
  BnestApp keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # Temporary. Every entry is a module not yet moved into a strict context
  # boundary that a module outside this root calls. Delete entries as each
  # context lands; the closure unit requires this list empty.
  @legacy_exports [
    AdminConfig.Registry,
    Backup.Config,
    Deployment,
    FamilyChat,
    FamilyChat.Store,
    PushNotifications,
    Scheduler,
    Scheduler.Policy,
    Scheduler.Registry,
    Scheduler.Run,
    Scheduler.Store
  ]

  use Boundary,
    deps: [
      BnestApp.SqliteRepo,
      BnestApp.Storage,
      # legacy: infrastructure the legacy modules call directly. Each entry leaves
      # with its last legacy caller, when that context's adapters take the call over.
      Ecto.Migrator,
      Ecto.Query,
      Ecto.UUID,
      Exqlite,
      Req,
      WebPush
    ],
    exports: @legacy_exports
end
