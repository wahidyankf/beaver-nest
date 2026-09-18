defmodule BnestApp.SqliteRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :bnest_app,
    adapter: Ecto.Adapters.SQLite3

  # Asks the pool's own live connection what file it actually has open,
  # rather than independently recomputing the path from
  # `BnestApp.Storage.Config`. The two can legitimately diverge (Family
  # Chat's isolated test database is one example -- see
  # `BnestApp.FamilyChat.Store.database_path/0`'s own comment), and a
  # backup/capacity guard that reads the wrong file silently measures or
  # snapshots the wrong database.
  @spec main_database_path() :: String.t()
  def main_database_path do
    %{rows: [[_seq, "main", path]]} = query!("PRAGMA database_list")
    path
  end
end
