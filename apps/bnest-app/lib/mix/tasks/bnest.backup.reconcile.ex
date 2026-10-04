defmodule Mix.Tasks.Bnest.Backup.Reconcile do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.Reconciliation
  alias BnestApp.Scheduler
  alias BnestApp.Storage

  @shortdoc "Reports whether the artifacts of the verified backup runs are still on disk"

  @handler_key "prod_sqlite_backup"

  # The task reads the ledger from a scratch copy of the database (`Storage.with_database_copy/2`)
  # and never starts the application: `app.start` would start the Scheduler against the
  # production runtime root, and a tick could claim a slot. Nothing here may call it, and
  # `:scheduler_automatic?` is switched off first as a second guard, so that a Scheduler
  # started by mistake would not tick.
  @impl Mix.Task
  def run(arguments) do
    if arguments != [], do: Mix.raise("usage: mix bnest.backup.reconcile")

    Mix.Task.run("app.config")
    Application.put_env(:bnest_app, :scheduler_automatic?, false)
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    arguments |> read_copy() |> print()
  end

  @doc """
  The check itself, over the database this VM has started: the destination read from
  configuration and its marker, never created, marked or restricted (`Backup.read_destination/0`),
  the ledger read through the Scheduler, and the words of the result. Its
  `exit_status` is zero only when at least one backup is expected and every one is present.
  A read that raises, or a destination or ledger that cannot be read, is reported as a check
  that could not be made, never with its reason, which may name a path.
  """
  @spec execute([String.t()]) :: %{exit_status: 0 | 1, lines: [String.t()]}
  def execute(_arguments) do
    report = Reconciliation.report(outcome())
    %{exit_status: report.exit_status, lines: Reconciliation.render(report)}
  end

  defp outcome do
    with {:ok, location} <- Backup.read_destination() do
      Backup.reconcile(location.directory, Scheduler.verified_runs(@handler_key))
    end
  rescue
    _error -> {:error, :raised}
  catch
    :exit, _reason -> {:error, :exited}
  end

  # Two copies of the ledger are the same when they hold as many verified runs, the latest of
  # which finished at the same time.
  defp ledger_fingerprint do
    runs = Scheduler.verified_runs(@handler_key)
    {length(runs), runs |> List.last() |> finished_at()}
  end

  defp finished_at(nil), do: nil
  defp finished_at(run), do: run.finished_at

  defp read_copy(arguments) do
    case Storage.with_database_copy(&ledger_fingerprint/0, fn -> execute(arguments) end) do
      {:ok, result} -> result
      {:error, reason} -> unchecked(reason)
    end
  rescue
    _error -> unchecked(:raised)
  catch
    :exit, _reason -> unchecked(:exited)
  end

  defp unchecked(reason) do
    report = Reconciliation.report({:error, reason})
    %{exit_status: report.exit_status, lines: Reconciliation.render(report), reason: reason}
  end

  defp print(result) do
    Enum.each(result.lines, &Mix.shell().info/1)
    explain(result[:reason])
    if result.exit_status != 0, do: exit({:shutdown, result.exit_status})
  end

  # What went wrong in the task rather than in the backups, so the operator knows to run it
  # again: a fixed sentence, never an error's own message.
  defp explain(:unstable),
    do: Mix.shell().error("ledger unstable: it changed between two copies, so it was not read")

  defp explain(:copy_failed), do: Mix.shell().error("the database could not be copied")
  defp explain(_reason), do: :ok
end
