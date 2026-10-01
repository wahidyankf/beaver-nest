defmodule BnestApp.Storage.Adapters.LocalMaintenance do
  @moduledoc """
  The storage maintenance procedures on this host's flat files and SQLite database. Each one
  delegates to the adapter that owns its effects.
  """

  @behaviour BnestApp.Storage.Ports.Maintenance

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.FlatRetirement
  alias BnestApp.Storage.Adapters.SchemaAudit
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Storage.Adapters.SqliteMigration
  alias BnestApp.Storage.Adapters.SqliteRelocation
  alias BnestApp.Storage.Adapters.TestDataCleanup

  @impl true
  def run_migration(flat_root), do: SqliteMigration.run(flat_root)

  @impl true
  def migration_blocked?, do: SqliteMigration.blocked?()

  # A fresh database has no migration tables yet, and an unreachable one cannot have started a
  # migration, so both read as "not started".
  @impl true
  def migration_started? do
    SqliteCoordinator.ensure_started!()

    SqliteRepo.query("SELECT 1 FROM sqlite_master WHERE name = 'bnest_migration_runs'")
    |> case do
      {:ok, %{rows: [[1]]}} ->
        match?(
          {:ok, %{rows: [_row]}},
          SqliteRepo.query("SELECT 1 FROM bnest_migration_runs LIMIT 1")
        )

      _missing_table ->
        false
    end
  rescue
    _error -> false
  end

  @impl true
  def parity_ok?(flat_root), do: SqliteMigration.parity_ok?(flat_root)

  @impl true
  def integrity_ok?, do: SqliteMigration.integrity_ok?()

  @impl true
  def restore_rehearsal_ok? do
    destination =
      Path.join(
        System.tmp_dir!(),
        "bnest-storage-restore-rehearsal-#{System.unique_integer([:positive])}.sqlite3"
      )

    SqliteMigration.restore_rehearsal(destination)
  end

  @impl true
  def activate_sqlite!, do: SqliteMigration.activate!()

  @impl true
  def relocate(directory), do: SqliteRelocation.run(directory)

  @impl true
  def retire(flat_root, generation, true), do: FlatRetirement.verify(flat_root, generation)
  def retire(flat_root, generation, false), do: FlatRetirement.run(flat_root, generation)

  @impl true
  def purge_test_data(generation, true), do: TestDataCleanup.verify(generation)
  def purge_test_data(generation, false), do: TestDataCleanup.run(generation)

  @impl true
  def audit_schema(root), do: SchemaAudit.audit_root(root)
end
