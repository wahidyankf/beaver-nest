defmodule BnestApp.Storage.Adapters.SqliteMigration do
  @moduledoc """
  The flat-file migration's SQLite target: the `bnest_migration_runs` and
  `bnest_migration_items` ledger, the migrated `bnest_records` rows, and the preserved
  `bnest_recovery_sources`, plus the database's integrity and restore checks.
  `BnestApp.Storage.Migration` decides what to write.
  """

  @behaviour BnestApp.Storage.Ports.MigrationLedger

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.SqliteRecordBackend

  import Ecto.Query

  @impl true
  def run_started?(migration_id) do
    from(r in "bnest_migration_runs", where: r.migration_id == ^migration_id)
    |> SqliteRepo.exists?()
  end

  @impl true
  def start_run!(run) do
    SqliteRepo.insert_all("bnest_migration_runs", [run])
    :ok
  end

  @impl true
  def update_run!(migration_id, state, fingerprint) do
    from(r in "bnest_migration_runs", where: r.migration_id == ^migration_id)
    |> SqliteRepo.update_all(set: [state: state, source_fingerprint: fingerprint])

    :ok
  end

  @impl true
  def mark_verified!(migration_id, verified_at) do
    from(r in "bnest_migration_runs", where: r.migration_id == ^migration_id)
    |> SqliteRepo.update_all(set: [state: "verified", verified_at: verified_at])

    :ok
  end

  @impl true
  def item(migration_id, relative_path) do
    from(i in "bnest_migration_items",
      where: i.migration_id == ^migration_id and i.source_relative_path == ^relative_path,
      select: %{outcome: i.outcome, source_sha256: i.source_sha256}
    )
    |> SqliteRepo.one()
  end

  @impl true
  def put_item!(item) do
    SqliteRepo.insert_all("bnest_migration_items", [item],
      on_conflict: {:replace, [:source_sha256, :target_sha256, :outcome, :error_category]},
      conflict_target: [:migration_id, :source_relative_path]
    )

    :ok
  end

  @impl true
  def blocked? do
    from(i in "bnest_migration_items", where: i.outcome in ["invalid", "changed", "failed"])
    |> SqliteRepo.exists?()
  end

  @impl true
  def put_record!(classification, record, target_sha256, now) do
    SqliteRepo.insert_all(
      "bnest_records",
      [
        %{
          record_type: classification.record_type,
          record_key: classification.record_key,
          owner_id: classification.owner_id,
          schema_version: record["schemaVersion"],
          revision: record["revision"],
          payload_json: Jason.encode!(record),
          payload_sha256: target_sha256,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict:
        {:replace,
         [:owner_id, :schema_version, :revision, :payload_json, :payload_sha256, :updated_at]},
      conflict_target: [:record_type, :record_key]
    )

    :ok
  end

  @impl true
  def read_record(type, identity),
    do: SqliteRecordBackend.read(SqliteRecordBackend.new(SqliteRepo), type, identity)

  @impl true
  def put_recovery_source!(recovery_source) do
    SqliteRepo.insert_all("bnest_recovery_sources", [recovery_source],
      on_conflict: :nothing,
      conflict_target: [:owner_kind, :owner_key, :import_id]
    )

    :ok
  end

  @impl true
  def recovery_source(owner_kind, owner_key, import_id) do
    case SqliteRepo.query!(
           "SELECT payload_blob, payload_sha256, byte_size FROM bnest_recovery_sources WHERE owner_kind = ? AND owner_key = ? AND import_id = ?",
           [owner_kind, owner_key, import_id]
         ).rows do
      [[payload, payload_sha256, byte_size]] ->
        %{payload: payload, payload_sha256: payload_sha256, byte_size: byte_size}

      _absent ->
        nil
    end
  end

  @spec integrity_ok?(module()) :: boolean()
  def integrity_ok?(repo \\ SqliteRepo) do
    case repo.query("PRAGMA quick_check") do
      {:ok, %{rows: [["ok"]]}} -> true
      _other -> false
    end
  end

  @spec restore_rehearsal(String.t(), module()) :: boolean()
  def restore_rehearsal(destination_path, repo \\ SqliteRepo) do
    File.rm(destination_path)
    {:ok, _result} = repo.query("VACUUM INTO ?", [destination_path])
    ok = File.exists?(destination_path)
    File.rm(destination_path)
    ok
  end
end
