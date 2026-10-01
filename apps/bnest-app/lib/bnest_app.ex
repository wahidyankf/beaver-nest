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
    Chat,
    Codex.ModelAccess,
    Codex.ModelCatalog,
    Codex.RepositoryAccess,
    Codex.Settings,
    DataRepository,
    DataRepository.Import,
    DataRepository.Schema,
    DataRepository.StorageCoordinator,
    DataRepository.Store,
    Deployment,
    FamilyChat,
    FamilyChat.Store,
    Identity,
    Identity.Session,
    PushNotifications,
    Scheduler,
    Scheduler.Policy,
    Scheduler.Registry,
    Scheduler.Run,
    Scheduler.Store,
    SifatAllah,
    Storage.Config,
    Storage.Location,
    Storage.Lock,
    Storage.Migration,
    Storage.Relocation,
    Storage.Retirement,
    Storage.TestDataCleanup
  ]

  # Infrastructure the legacy modules call directly. Each entry leaves with the
  # last legacy caller, when that context's adapters take the call over.
  @legacy_infrastructure [Argon2, Ecto.Migrator, Ecto.Query, Ecto.UUID, Exqlite, Req, WebPush]

  use Boundary,
    deps: [BnestApp.SqliteRepo | @legacy_infrastructure],
    exports: @legacy_exports
end
