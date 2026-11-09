defmodule BnestApp.Test.UnfinishableDatabaseSnapshot do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  # A database snapshot whose copy cannot finish before any deadline a test can set. A real
  # `VACUUM INTO` of the test database ends in milliseconds, so a short timeout only races it:
  # a host that delays the caller by that long lets the copy win. This copy leaves a partial
  # file, as the port allows, then runs a statement that takes far longer than the deadline
  # through the adapter's own deadline and cancellation, so the cooperative cancel always
  # reaches a statement that is still running. Every other operation is the real adapter's.

  @behaviour BnestApp.Backup.Ports.DatabaseSnapshot

  alias BnestApp.Backup.Adapters.SqliteDatabaseSnapshot
  alias BnestApp.Backup.Ports.DatabaseSnapshot
  alias BnestApp.SqliteRepo

  # Far beyond the longest deadline a test sets even at SQLite's fastest step rate, yet bounded
  # so that a cancel lost before the statement started cannot leave it running for good.
  @runaway_rows 200_000_000
  @runaway_statement """
  WITH RECURSIVE counter(n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM counter WHERE n < #{@runaway_rows}
  ) SELECT count(*) FROM counter
  """

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def source_path(_snapshot), do: DatabaseSnapshot.source_path(SqliteDatabaseSnapshot.new())

  @impl true
  def source_generation(_snapshot),
    do: DatabaseSnapshot.source_generation(SqliteDatabaseSnapshot.new())

  @impl true
  def vacuum_into(_snapshot, partial_path, timeout_ms) do
    File.write!(partial_path, "partial copy")

    SqliteDatabaseSnapshot.execute_within_deadline(
      SqliteRepo.main_database_path(),
      @runaway_statement,
      timeout_ms
    )
  end

  @impl true
  def prove(_snapshot, path), do: DatabaseSnapshot.prove(SqliteDatabaseSnapshot.new(), path)

  @impl true
  def restore(_snapshot, artifact_path),
    do: DatabaseSnapshot.restore(SqliteDatabaseSnapshot.new(), artifact_path)

  @impl true
  def restore_roots(_snapshot),
    do: DatabaseSnapshot.restore_roots(SqliteDatabaseSnapshot.new())
end
