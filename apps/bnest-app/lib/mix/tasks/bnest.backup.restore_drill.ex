defmodule Mix.Tasks.Bnest.Backup.RestoreDrill do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.RestoreDrillReport

  @shortdoc "Proves one backup artifact restores into an isolated root and reads back"

  @usage "usage: mix bnest.backup.restore_drill --artifact <basename>"

  # The drill needs no database of its own, so it starts none: `app.start` would start the
  # Scheduler and the repository on the production database, `Backup.run/1` would snapshot it
  # and `Storage.ensure_started!` would open it. Nothing here may call them. `Backup.restore/1`
  # restores into a root of its own, from the artifact, over a connection it opens itself, which
  # needs only the SQLite driver. `:scheduler_automatic?` is switched off first as a second
  # guard, so that a Scheduler started by mistake would not tick.
  @impl Mix.Task
  def run(["--artifact", basename] = arguments) when is_binary(basename) do
    Mix.Task.run("app.config")
    Application.put_env(:bnest_app, :scheduler_automatic?, false)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    result = execute(arguments)
    Enum.each(result.lines, &Mix.shell().info/1)
    if result.exit_status != 0, do: exit({:shutdown, result.exit_status})
  end

  def run(_arguments), do: Mix.raise(@usage)

  @doc """
  The drill itself, over the VM's configuration: the destination read as
  `Backup.read_destination/0` names it, never created, marked or restricted; the artifact
  accepted only as the bare name of a regular file inside it (`Backup.restore_target/2`); one
  restore through `Backup.restore/1`; and the words of the result. Its `exit_status` is zero
  only when the evidence reads back whole and the restore left no root behind. A failure is
  reported as a fixed line, never with the failure's own message, which may name a path.
  """
  @spec execute([String.t()]) :: %{exit_status: 0 | 1, lines: [String.t()]}
  def execute(["--artifact", basename]) do
    basename |> outcome() |> RestoreDrillReport.report()
  end

  defp outcome(basename) do
    with {:ok, location} <- destination(),
         {:ok, target} <- target(location.directory, basename) do
      restore(target)
    end
  end

  defp destination do
    case Backup.read_destination() do
      {:ok, location} -> {:ok, location}
      {:error, _reason} -> {:error, :destination_unreadable}
    end
  rescue
    _error -> {:error, :destination_unreadable}
  catch
    :exit, _reason -> {:error, :destination_unreadable}
  end

  defp target(directory, basename) do
    case Backup.restore_target(directory, basename) do
      {:ok, target} -> {:ok, target}
      {:error, :refused} -> :refused
    end
  end

  # The roots present before the restore are not its to remove, so only a root that is there
  # afterwards and was not there before counts as left behind.
  defp restore(target) do
    before = Backup.restore_roots()

    case Backup.restore(target) do
      {:ok, %{evidence: evidence}} -> {:restored, evidence, Backup.restore_roots() -- before}
      {:error, _reason} -> {:error, :restore_failed}
    end
  rescue
    _error -> {:error, :restore_failed}
  catch
    :exit, _reason -> {:error, :restore_failed}
  end
end
