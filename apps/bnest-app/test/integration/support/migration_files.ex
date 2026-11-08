defmodule BnestApp.Test.MigrationFiles do
  @moduledoc """
  The migration versions the release ships, read from `priv/sqlite_repo/migrations` at test time.
  A version is the numeric prefix of a migration file name. Tests compare what a database has
  applied with this list, so a skipped or an extra migration fails them. Integration layer only:
  `test/support` may not name the migrations directory.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @doc "The sorted versions of every migration file in the directory."
  @spec versions() :: [integer()]
  def versions do
    Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations/*.exs")
    |> Path.wildcard()
    |> Enum.map(fn path -> path |> Path.basename() |> String.split("_", parts: 2) |> hd() end)
    |> Enum.map(&String.to_integer/1)
    |> Enum.sort()
  end
end
