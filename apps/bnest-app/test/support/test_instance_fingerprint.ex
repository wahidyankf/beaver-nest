defmodule BnestApp.TestInstance.Fingerprint do
  @moduledoc false

  # The schema identity of a database, as ADR 001 section 4 defines it: SHA-256 over the sorted
  # schema objects and the sorted applied migration versions. Rows and seeds are not part of it;
  # the schema-parity test checks the release seeds on their own.
  #
  # `current/0` reads through `SqliteRepo`, the connection the app uses, and only `SELECT`s. The
  # source scan therefore has nothing to refuse here.

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.SqliteRepo

  @objects_query """
  SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'
  """
  @versions_query "SELECT version FROM schema_migrations"

  @doc "The fingerprint of the database the running repo is connected to."
  @spec current() :: String.t()
  def current do
    %{rows: object_rows} = SqliteRepo.query!(@objects_query)
    %{rows: version_rows} = SqliteRepo.query!(@versions_query)

    digest(object_rows, Enum.map(version_rows, fn [version] -> version end))
  end

  @doc """
  The digest of schema object rows and migration versions. It is pure: the order of the rows and of
  the versions does not change it. The rows are encoded as JSON, so field boundaries cannot shift.
  """
  @spec digest([[term()]], [integer()]) :: String.t()
  def digest(object_rows, versions) do
    payload = Jason.encode!([Enum.sort(object_rows), Enum.sort(versions)])

    :sha256
    |> :crypto.hash(payload)
    |> Base.encode16(case: :lower)
  end
end
