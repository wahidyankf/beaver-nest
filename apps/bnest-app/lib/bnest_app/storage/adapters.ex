defmodule BnestApp.Storage.Adapters do
  @moduledoc """
  Storage's outbound adapters: the flat-file and SQLite record backends, the storage pointer
  and lock files, the SQLite lifecycle, and the migration, relocation, retirement, cleanup,
  audit and scratch-copy procedures. Only configuration and the composition root name them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [
      BnestApp.Storage,
      BnestApp.SqliteRepo,
      Ecto.Adapters.SQL,
      Ecto.Migrator,
      Ecto.Query,
      Exqlite,
      Jason
    ],
    exports: :all
end
