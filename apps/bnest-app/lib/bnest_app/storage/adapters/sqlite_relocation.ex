defmodule BnestApp.Storage.Adapters.SqliteRelocation do
  @moduledoc false

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.FileLock
  alias BnestApp.Storage.Adapters.SqliteCoordinator

  @spec run(String.t()) :: {:ok, map()} | {:error, atom()}
  def run(destination_directory \\ Storage.default_directory()) do
    FileLock.with_exclusive(fn -> relocate(destination_directory) end)
  end

  defp relocate(destination_directory) do
    with {:ok, config} <- FileConfigStore.read(),
         true <- config["phase"] == "sqlite_primary" || {:error, :not_sqlite_primary},
         {:ok, destination_directory} <- FileConfigStore.validate_directory(destination_directory) do
      source = Path.join(config["databaseDirectory"], config["databaseFilename"])
      destination = Path.join(destination_directory, config["databaseFilename"])

      if source == destination do
        verify_current(config)
      else
        relocate_database(config, source, destination, destination_directory)
      end
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :not_sqlite_primary}
    end
  end

  defp verify_current(config) do
    SqliteCoordinator.ensure_started!(FileConfigStore.resolved_database_path())

    if proof(SqliteRepo).integrity == [["ok"]] do
      {:ok, config}
    else
      {:error, :integrity_failed}
    end
  end

  defp relocate_database(config, source, destination, destination_directory) do
    if File.exists?(destination) do
      {:error, :destination_exists}
    else
      File.mkdir_p!(destination_directory)
      File.chmod!(destination_directory, 0o700)
      temporary = destination <> ".relocating-" <> random_id()

      try do
        SqliteCoordinator.ensure_started!(source)
        source_proof = proof(SqliteRepo)
        ensure_integrity!(source_proof)
        SqliteRepo.query!("PRAGMA wal_checkpoint(FULL)")
        SqliteRepo.query!("VACUUM INTO ?", [temporary])
        File.chmod!(temporary, 0o600)

        SqliteCoordinator.stop()
        SqliteCoordinator.ensure_started!(temporary)
        destination_proof = proof(SqliteRepo)
        ensure_matching!(source_proof, destination_proof)
        SqliteCoordinator.stop()

        File.rename!(temporary, destination)
        SqliteCoordinator.ensure_started!(destination)
        ensure_matching!(source_proof, proof(SqliteRepo))

        generation = random_id()
        updated = FileConfigStore.relocate!(destination_directory, generation)
        {:ok, updated}
      rescue
        error ->
          SqliteCoordinator.stop()
          File.rm(temporary)
          File.rm(destination)
          FileConfigStore.restore!(config)
          SqliteCoordinator.ensure_started!(source)
          reraise error, __STACKTRACE__
      end
    end
  end

  defp proof(repo) do
    %{
      integrity: repo.query!("PRAGMA quick_check").rows,
      records:
        repo.query!(
          "SELECT record_type, record_key, payload_sha256 FROM bnest_records ORDER BY record_type, record_key"
        ).rows,
      recovery:
        repo.query!(
          "SELECT owner_kind, owner_key, import_id, payload_sha256 FROM bnest_recovery_sources ORDER BY owner_kind, owner_key, import_id"
        ).rows,
      migration_runs:
        repo.query!(
          "SELECT migration_id, source_fingerprint, ddl_checksum, state FROM bnest_migration_runs ORDER BY migration_id"
        ).rows,
      migration_items:
        repo.query!(
          "SELECT migration_id, source_relative_path, source_sha256, target_sha256, outcome FROM bnest_migration_items ORDER BY migration_id, source_relative_path"
        ).rows,
      ecto_versions: repo.query!("SELECT version FROM schema_migrations ORDER BY version").rows
    }
  end

  defp ensure_integrity!(%{integrity: [["ok"]]}), do: :ok
  defp ensure_integrity!(_proof), do: raise("SQLite integrity check failed")

  defp ensure_matching!(source, destination) do
    ensure_integrity!(destination)
    if source != destination, do: raise("SQLite logical relocation proof failed")
  end

  defp random_id,
    do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
end
