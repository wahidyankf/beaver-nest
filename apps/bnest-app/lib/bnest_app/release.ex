defmodule BnestApp.Release do
  @moduledoc """
  Release-time entry points that `tools/deployment.mjs` evaluates by name: the domain
  migrations and the Caddy configuration. They are infrastructure entry points, so this
  boundary may reach `BnestApp.SqliteRepo` and the Ecto migrator directly.
  """

  use Boundary,
    top_level?: true,
    deps: [
      BnestApp.FamilyChat,
      BnestApp.Scheduler,
      BnestApp.SqliteRepo,
      BnestApp.Storage,
      Ecto.Adapters.SQL,
      Ecto.Migrator
    ],
    exports: [Migrations]
end
