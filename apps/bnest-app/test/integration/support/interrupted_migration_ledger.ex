defmodule BnestApp.Test.InterruptedMigrationLedger do
  @moduledoc """
  The production SQLite migration ledger, interrupted: `install/1` puts it in place of
  `SqliteMigration` for the calling process, which may then write `count` migrated records
  before every later record write fails as a killed migration would. Each callback otherwise
  goes to `SqliteMigration`. `uninstall/1` puts the previous Storage configuration back.
  """

  @behaviour BnestApp.Storage.Ports.MigrationLedger

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Storage.Adapters.SqliteMigration

  @budget {__MODULE__, :record_writes}

  @spec install(non_neg_integer()) :: keyword()
  def install(count) do
    previous = Application.fetch_env!(:bnest_app, BnestApp.Storage)
    Process.put(@budget, count)

    Application.put_env(
      :bnest_app,
      BnestApp.Storage,
      Keyword.put(previous, :migration_ledger, __MODULE__)
    )

    previous
  end

  @spec uninstall(keyword()) :: :ok
  def uninstall(previous) do
    Process.delete(@budget)
    Application.put_env(:bnest_app, BnestApp.Storage, previous)
  end

  @impl true
  def put_record!(classification, record, target_sha256, now) do
    case Process.get(@budget, 0) do
      0 -> raise "the migration was interrupted before this record write"
      count -> Process.put(@budget, count - 1)
    end

    SqliteMigration.put_record!(classification, record, target_sha256, now)
  end

  @impl true
  defdelegate run_started?(migration_id), to: SqliteMigration

  @impl true
  defdelegate start_run!(run), to: SqliteMigration

  @impl true
  defdelegate update_run!(migration_id, state, fingerprint), to: SqliteMigration

  @impl true
  defdelegate mark_verified!(migration_id, verified_at), to: SqliteMigration

  @impl true
  defdelegate item(migration_id, relative_path), to: SqliteMigration

  @impl true
  defdelegate put_item!(item), to: SqliteMigration

  @impl true
  defdelegate blocked?(), to: SqliteMigration

  @impl true
  defdelegate read_record(type, identity), to: SqliteMigration

  @impl true
  defdelegate put_recovery_source!(row), to: SqliteMigration

  @impl true
  defdelegate recovery_source(owner_kind, owner_key, import_id), to: SqliteMigration
end
