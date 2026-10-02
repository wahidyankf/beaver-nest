defmodule BnestApp.Backup.Adapters do
  @moduledoc """
  Backup's adapters: the configuration file, the destination's files, the SQLite snapshot,
  the `df` capacity probe and the `git` ignore check (outbound), and the Scheduler's backup
  task (inbound). Only configuration names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [
      BnestApp.Backup,
      BnestApp.Scheduler,
      BnestApp.SqliteRepo,
      BnestApp.Storage,
      Exqlite,
      Jason
    ],
    exports: :all
end
