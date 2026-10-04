defmodule BnestApp.Backup.Adapters.ScheduledBackupTask do
  @moduledoc """
  Inbound adapter: the Scheduler task configuration registers under `"prod_sqlite_backup"`
  (the handler `family_chat_operations.feature` still calls "Backup.Run"). It translates one
  claimed run into Backup facade calls and owns only the Scheduler's claim and lease
  bookkeeping: whether a setup claim still names the configured destination, the late
  lease check before promotion, and recording the run through the Scheduler facade. Every
  backup mechanic (capacity, `VACUUM INTO`, independent proof, receipt, retention) is
  `BnestApp.Backup`'s, so this module runs no SQL of its own.

  Once a run is recorded and retention has run, it checks the destination against the ledger
  (`BnestApp.Backup.reconcile/2` over `BnestApp.Scheduler.verified_runs/1`, the one place the
  two are composed on this side) and reports the result through one
  `[:bnest_app, :backup, :integrity]` telemetry event and one log entry, both in the words of
  `BnestApp.Backup.Domain.Reconciliation`. That check never fails the run: it can only be
  reported, and one that raises is reported as a check that could not be made.
  """

  @behaviour BnestApp.Scheduler.Ports.Task

  require Logger

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.Reconciliation
  alias BnestApp.Scheduler

  @handler_key "prod_sqlite_backup"

  @impl Scheduler.Ports.Task
  def execute(claim, %DateTime{} = now) do
    with {:ok, location} <- Backup.destination(),
         :ok <- destination_matches(claim, location),
         {:ok, artifact} <- run_backup(claim, location, now),
         {:ok, receipt} <- Backup.record_receipt(claim, location, now, artifact),
         :ok <- Scheduler.complete_run(claim.run_id, claim.attempt, receipt, now) do
      {:ok, _retained} = Backup.retain_owned(location.directory)
      reconcile(location.directory)
      {:ok, receipt}
    else
      {:error, :destination_changed} ->
        _result = Scheduler.skip_run(claim.run_id, claim.attempt, :destination_changed, now)
        {:skipped, :destination_changed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The check after the run: does the destination still hold the artifact of every verified
  # run retention keeps? The result is only reported, never acted on.
  defp reconcile(directory) do
    directory
    |> check()
    |> Reconciliation.report()
    |> announce()
  end

  # The run this follows is already recorded verified, so a check that raises or exits must
  # never fail it: it is reported as a check that could not be made. The reason is dropped,
  # because a raised error's message may name a path.
  defp check(directory) do
    Backup.reconcile(directory, Scheduler.verified_runs(@handler_key))
  rescue
    _error -> {:error, :raised}
  catch
    :exit, _reason -> {:error, :exited}
  end

  # One telemetry event and one log entry, both from the words of `Reconciliation` alone: a
  # healthy result is information, anything else an error.
  defp announce(report) do
    :telemetry.execute(
      [:bnest_app, :backup, :integrity],
      %{problem_count: length(report.problems)},
      Map.take(report, [:summary, :problems, :exit_status])
    )

    Logger.log(
      if(report.exit_status == 0, do: :info, else: :error),
      Enum.join(Reconciliation.render(report), "\n")
    )
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
