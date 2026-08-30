defmodule BnestApp.Backup.Run do
  @moduledoc false

  alias BnestApp.Backup.Config
  alias BnestApp.Backup.Location
  alias BnestApp.Backup.Receipt
  alias BnestApp.Scheduler.Policy
  alias BnestApp.Scheduler.Store
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig

  @scope "bnest-production-backups-v1"

  @spec execute(map(), DateTime.t()) :: {:ok, map()} | {:skipped, atom()} | {:error, atom()}
  def execute(claim, %DateTime{} = now) do
    with {:ok, location} <- Config.resolve(),
         :ok <- destination_matches(claim, location),
         {:ok, receipt} <- create_backup(claim, location, now),
         :ok <- Store.complete(claim.run_id, claim.attempt, receipt, now) do
      retain_owned(location.directory)
      {:ok, receipt}
    else
      {:error, :destination_changed} ->
        _result = Store.skip(claim.run_id, claim.attempt, :destination_changed, now)
        {:skipped, :destination_changed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec owned_receipts(String.t()) :: [map()]
  def owned_receipts(directory) do
    case Location.read_marker(directory) do
      {:ok, marker} ->
        directory
        |> Path.join("*.receipt.json")
        |> Path.wildcard()
        |> Enum.flat_map(&read_owned_receipt(&1, directory, marker["destinationId"]))
        |> Enum.sort_by(& &1["createdAt"], :desc)

      {:error, _reason} ->
        []
    end
  end

  defp destination_matches(%{claim_kind: "setup", claim_key: "setup:" <> claimed}, location) do
    if claimed == location.destination_id or
         String.starts_with?(claimed, location.destination_id <> "-"),
       do: :ok,
       else: {:error, :destination_changed}
  end

  defp destination_matches(_scheduled_claim, _location), do: :ok

  defp create_backup(claim, location, now) do
    timestamp = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    artifact_basename = "bnest-prod-#{timestamp}-#{claim.run_id}.sqlite3"
    artifact_path = Path.join(location.directory, artifact_basename)
    partial_path = artifact_path <> ".partial"

    try do
      File.rm(partial_path)
      SqliteRepo.query!("PRAGMA wal_checkpoint(FULL)")
      ensure_capacity!(location.directory)
      SqliteRepo.query!("VACUUM INTO ?", [partial_path])
      File.chmod!(partial_path, 0o600)

      proof = independent_proof!(partial_path)
      sync_file!(partial_path)
      ensure_active_attempt!(claim, now)
      File.rename!(partial_path, artifact_path)

      receipt = build_receipt(claim, location, now, artifact_basename, artifact_path, proof)
      receipt_path = String.replace_suffix(artifact_path, ".sqlite3", ".receipt.json")
      atomic_json!(receipt_path, receipt)
      {:ok, receipt}
    rescue
      _error ->
        File.rm(partial_path)
        {:error, :backup_failed}
    end
  end

  defp build_receipt(claim, location, now, basename, artifact_path, proof) do
    %{
      "schemaVersion" => 1,
      "ownershipScope" => @scope,
      "destinationId" => location.destination_id,
      "scheduleKey" => claim.schedule_key,
      "claimKind" => claim.claim_kind,
      "claimKey" => claim.claim_key,
      "scheduledFor" => nullable_iso(claim.scheduled_for),
      "runId" => claim.run_id,
      "scheduleRevision" => claim.schedule_revision,
      "createdAt" => iso8601(now),
      "sourceGeneration" => BnestApp.Storage.Config.database_generation(),
      "artifactBasename" => basename,
      "artifactSha256" => sha256_file(artifact_path),
      "artifactBytes" => File.stat!(artifact_path).size,
      "quickCheck" => "ok",
      "schemaVersions" => proof.schema_versions,
      "logicalProofSha256" => proof.logical_sha256
    }
  end

  defp independent_proof!(path) do
    {:ok, connection} = Exqlite.Sqlite3.open(path, mode: :readonly)

    try do
      [["ok"]] = query_rows(connection, "PRAGMA quick_check")

      schema_versions =
        connection
        |> query_rows("SELECT version FROM schema_migrations ORDER BY version")
        |> Enum.map(&hd/1)

      logical_rows =
        query_rows(
          connection,
          "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        )

      logical_sha256 =
        %{schema_versions: schema_versions, schema: logical_rows}
        |> Jason.encode!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      %{schema_versions: schema_versions, logical_sha256: logical_sha256}
    after
      :ok = Exqlite.Sqlite3.close(connection)
    end
  end

  defp query_rows(connection, sql) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(connection, sql)

    try do
      collect_rows(connection, statement, [])
    after
      :ok = Exqlite.Sqlite3.release(connection, statement)
    end
  end

  defp collect_rows(connection, statement, rows) do
    case Exqlite.Sqlite3.step(connection, statement) do
      {:row, row} -> collect_rows(connection, statement, [row | rows])
      :done -> Enum.reverse(rows)
      {:error, reason} -> raise "backup proof query failed: #{inspect(reason)}"
    end
  end

  defp retain_owned(directory) do
    receipts = owned_receipts(directory)

    kept =
      receipts
      |> Enum.group_by(&(&1["createdAt"] |> Policy.parse_datetime!() |> Policy.wib_date()))
      |> Enum.sort_by(fn {date, _receipts} -> date end, {:desc, Date})
      |> Enum.take(7)
      |> Enum.map(fn {_date, [newest | _older]} -> newest["runId"] end)
      |> MapSet.new()

    Enum.each(receipts, fn receipt ->
      unless MapSet.member?(kept, receipt["runId"]) do
        File.rm(Path.join(directory, receipt["artifactBasename"]))

        receipt["artifactBasename"]
        |> String.replace_suffix(".sqlite3", ".receipt.json")
        |> then(&File.rm(Path.join(directory, &1)))
      end
    end)
  end

  defp read_owned_receipt(path, directory, destination_id) do
    with {:ok, bytes} <- File.read(path),
         {:ok, receipt} <- Jason.decode(bytes),
         true <- Receipt.valid?(receipt, destination_id),
         artifact_path = Path.join(directory, receipt["artifactBasename"]),
         true <- File.regular?(artifact_path),
         true <- sha256_file(artifact_path) == receipt["artifactSha256"] do
      [receipt]
    else
      _unowned -> []
    end
  end

  defp atomic_json!(path, value) do
    temporary = path <> ".partial"
    File.write!(temporary, Jason.encode!(value))
    File.chmod!(temporary, 0o600)
    sync_file!(temporary)
    File.rename!(temporary, path)
  end

  defp sync_file!(path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :binary])
    :ok = :file.sync(file)
    :ok = :file.close(file)
  end

  defp ensure_active_attempt!(claim, now) do
    unless Store.active_attempt?(claim.run_id, claim.attempt, now) do
      raise "stale backup attempt"
    end
  end

  defp ensure_capacity!(directory) do
    source_bytes = StorageConfig.resolved_database_path() |> File.stat!() |> Map.fetch!(:size)
    required_bytes = source_bytes * 2 + 256 * 1024 * 1024

    unless available_bytes!(directory) >= required_bytes do
      raise "insufficient backup capacity"
    end
  end

  defp available_bytes!(directory) do
    {output, 0} = System.cmd("df", ["-Pk", directory], stderr_to_stdout: true)

    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.at(3)
    |> String.to_integer()
    |> Kernel.*(1024)
  end

  defp sha256_file(path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :binary, :raw])

    try do
      file
      |> hash_chunks(:crypto.hash_init(:sha256))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    after
      :ok = :file.close(file)
    end
  end

  defp hash_chunks(file, hash) do
    case :file.read(file, 64 * 1024) do
      {:ok, bytes} -> hash_chunks(file, :crypto.hash_update(hash, bytes))
      :eof -> hash
      {:error, reason} -> raise "backup digest failed: #{inspect(reason)}"
    end
  end

  defp nullable_iso(nil), do: nil
  defp nullable_iso(value), do: iso8601(value)
  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
