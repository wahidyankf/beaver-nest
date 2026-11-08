defmodule BnestApp.SqliteRepo do
  @moduledoc false

  use Boundary, top_level?: true, deps: [Ecto.Adapters.SQL, Ecto.Multi, Ecto.Repo], exports: []

  use Ecto.Repo,
    otp_app: :bnest_app,
    adapter: Ecto.Adapters.SQLite3

  # Asks the pool's own live connection what file it actually has open,
  # rather than independently recomputing the path from
  # `BnestApp.Storage`. The two can legitimately diverge (Family
  # Chat's isolated test database is one example -- see
  # `BnestApp.FamilyChat.Adapters.SqliteRoomStore`'s `database_path/1`), and a
  # backup/capacity guard that reads the wrong file silently measures or
  # snapshots the wrong database.
  # A connection that has used a temp schema lists `temp` as well, so the `main` row is selected by name.
  @spec main_database_path() :: String.t()
  def main_database_path do
    %{rows: rows} = query!("PRAGMA database_list")
    [_seq, "main", path] = Enum.find(rows, &match?([_seq, "main", _file], &1))
    path
  end
end
