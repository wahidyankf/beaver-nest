defmodule BnestApp.SqliteRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :bnest_app,
    adapter: Ecto.Adapters.SQLite3
end
