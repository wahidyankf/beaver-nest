defmodule BnestApp.Backup.Adapters.ScheduledBackupTask do
  @moduledoc """
  Inbound adapter: the Scheduler task configuration registers under `"prod_sqlite_backup"`
  (the handler `family_chat_operations.feature` still calls "Backup.Run"). It translates one
  claimed run into Backup facade calls and owns only the Scheduler's claim and lease
  bookkeeping: whether a setup claim still names the configured destination, the late
  lease check before promotion, and recording the run through the Scheduler facade. Every
  backup mechanic (capacity, `VACUUM INTO`, independent proof, receipt, retention) is
  `BnestApp.Backup`'s, so this module runs no SQL of its own.
  """

  @behaviour BnestApp.Scheduler.Ports.Task

  alias BnestApp.Backup
  alias BnestApp.Scheduler

  @impl Scheduler.Ports.Task
  def execute(claim, %DateTime{} = now) do
    with {:ok, location} <- Backup.destination(),
         :ok <- destination_matches(claim, location),
         {:ok, artifact} <- run_backup(claim, location, now),
         {:ok, receipt} <- Backup.record_receipt(claim, location, now, artifact),
         :ok <- Scheduler.complete_run(claim.run_id, claim.attempt, receipt, now) do
      {:ok, _retained} = Backup.retain_owned(location.directory)
      {:ok, receipt}
    else
      {:error, :destination_changed} ->
        _result = Scheduler.skip_run(claim.run_id, claim.attempt, :destination_changed, now)
        {:skipped, :destination_changed}

      {:error, reason} ->
        {:error, reason}
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
    if Scheduler.active_attempt?(claim.run_id, claim.attempt, now),
      do: :ok,
      else: {:error, :stale_claim}
  end
end
