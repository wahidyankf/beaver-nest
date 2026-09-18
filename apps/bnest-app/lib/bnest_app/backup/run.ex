defmodule BnestApp.Backup.Run do
  @moduledoc """
  The Scheduler-registered `"prod_sqlite_backup"` handler. Owns Scheduler
  claim/lease bookkeeping only (destination-continuity checking, the
  claim-shaped receipt, and `Store` persistence); every SQL-touching backup
  mechanic (capacity, `VACUUM INTO`, independent proof) is delegated to
  `BnestApp.Backup`, the public service, so this module runs no direct SQL
  of its own (`family_chat_operations.feature`'s "The Scheduler claims
  backup work only through the registered Backup.Run handler").
  """

  alias BnestApp.Backup
  alias BnestApp.Backup.Config
  alias BnestApp.Backup.Location
  alias BnestApp.Backup.Receipt
  alias BnestApp.Scheduler.Policy
  alias BnestApp.Scheduler.Store

  @spec execute(map(), DateTime.t()) :: {:ok, map()} | {:skipped, atom()} | {:error, atom()}
  def execute(claim, %DateTime{} = now) do
    with {:ok, location} <- Config.resolve(),
         :ok <- destination_matches(claim, location),
         {:ok, artifact} <- run_backup(claim, location, now),
         receipt = Receipt.build(claim, location, now, artifact),
         :ok <- write_receipt!(artifact.path, receipt),
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

  # `before_promote` re-checks this exact claim/attempt's lease as late as
  # possible -- immediately before `BnestApp.Backup` commits the artifact --
  # so a lease lost to a competing coordinator during the (potentially
  # long) `VACUUM INTO` cannot have its late result promoted as the
  # canonical one. A raised/`{:error, ...}` here becomes a distinct
  # `:stale_claim` retryable category rather than an opaque backup failure.
  defp run_backup(claim, location, now) do
    case Backup.run(
           deadline: now,
           destination_directory: location.directory,
           before_promote: fn -> stale_claim_check(claim, now) end
         ) do
      {:ok, artifact} -> {:ok, artifact}
      {:error, {:retryable, category, _artifact}} -> {:error, category}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stale_claim_check(claim, now) do
    if Store.active_attempt?(claim.run_id, claim.attempt, now),
      do: :ok,
      else: {:error, :stale_claim}
  end

  defp write_receipt!(artifact_path, receipt) do
    receipt_path = String.replace_suffix(artifact_path, ".sqlite3", ".receipt.json")
    atomic_json!(receipt_path, receipt)
    :ok
  end

  defp retain_owned(directory) do
    receipts = owned_receipts(directory)
    kept = retained_run_ids(receipts)

    Enum.each(receipts, fn receipt ->
      unless MapSet.member?(kept, receipt["runId"]) do
        File.rm(Path.join(directory, receipt["artifactBasename"]))

        receipt["artifactBasename"]
        |> String.replace_suffix(".sqlite3", ".receipt.json")
        |> then(&File.rm(Path.join(directory, &1)))
      end
    end)
  end

  @doc false
  @spec retained_run_ids([map()]) :: MapSet.t(String.t())
  def retained_run_ids(receipts) do
    receipts
    |> Enum.group_by(&(&1["createdAt"] |> Policy.parse_datetime!() |> Policy.wib_date()))
    |> Enum.sort_by(fn {date, _receipts} -> date end, {:desc, Date})
    |> Enum.take(7)
    |> Enum.map(fn {_date, [newest | _older]} -> newest["runId"] end)
    |> MapSet.new()
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
end
