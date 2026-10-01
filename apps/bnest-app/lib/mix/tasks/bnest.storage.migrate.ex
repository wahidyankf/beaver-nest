defmodule Mix.Tasks.Bnest.Storage.Migrate do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Storage

  @shortdoc "Runs the managed flat-file to SQLite storage migration without a browser visit"

  @impl Mix.Task
  def run(arguments) do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    {options, remaining, invalid} =
      OptionParser.parse(arguments, strict: [root: :string, activate: :boolean])

    if remaining != [] or invalid != [] do
      Mix.raise("usage: mix bnest.storage.migrate [--root <flat-root>] [--activate]")
    end

    flat_root = options[:root] || Application.fetch_env!(:bnest_app, :runtime_root)
    activate? = Keyword.get(options, :activate, false)

    case Storage.migrate(flat_root, activate?) do
      {:ok, outcome, report} ->
        report_run(report)
        report_verification(report)
        report_outcome(outcome)

      {:error, :blocked, report} ->
        report_run(report)

        Mix.raise(
          "migration blocked: resolve the malformed or changed source, then retry with the same identifier"
        )

      {:error, :verification_failed, report} ->
        report_run(report)
        report_verification(report)
        Mix.raise("verification failed; SQLite storage was not activated")
    end
  end

  defp report_run(%{run: run}) do
    Mix.shell().info(
      "migration #{run.migration_id}: accepted=#{run.accepted} blocked=#{run.blocked} " <>
        "unsupported=#{run.unsupported} state=#{run.state}"
    )
  end

  defp report_verification(%{verification: nil}), do: :ok

  defp report_verification(%{verification: verification}) do
    Mix.shell().info(
      "verification: parity=#{verification.parity} integrity=#{verification.integrity} " <>
        "restore=#{verification.restore}"
    )
  end

  defp report_outcome(:dry_run) do
    Mix.shell().info(
      "dry run complete; rerun with --activate once ready to switch storage authority"
    )
  end

  defp report_outcome(:activated),
    do: Mix.shell().info("storage authority switched to sqlite_primary")
end
