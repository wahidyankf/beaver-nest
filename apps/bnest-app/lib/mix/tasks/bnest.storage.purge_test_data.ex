defmodule Mix.Tasks.Bnest.Storage.PurgeTestData do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Storage

  @shortdoc "Removes verified legacy test identities from production SQLite"

  @usage "usage: mix bnest.storage.purge_test_data --generation <generation> [--dry-run]"

  @impl Mix.Task
  def run(arguments) do
    options = parse!(arguments)
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    case Storage.purge_test_data(options.generation, options.dry_run?) do
      {:ok, counts} ->
        print_report(options.dry_run?, {:ok, counts})

      {:error, reason} ->
        refuse(reason)
    end
  end

  # The option check runs before the application boots, so a usage refusal
  # never starts an application or touches configuration, a database or a
  # scheduler, and the unit layer can assert its wording without that boot.
  @doc """
  Validates the task's options before the application boots. Raises
  `Mix.Error` with the usage line when `--generation` is missing, or for an
  unknown option or a stray argument.
  """
  @spec parse!([String.t()]) :: %{generation: String.t(), dry_run?: boolean()}
  def parse!(arguments) do
    {options, remaining, invalid} =
      OptionParser.parse(arguments, strict: [generation: :string, dry_run: :boolean])

    if remaining != [] or invalid != [] or is_nil(options[:generation]) do
      Mix.raise(@usage)
    end

    %{generation: options[:generation], dry_run?: options[:dry_run] == true}
  end

  # The printed line is built by a pure function over the purge result, so
  # the unit layer can assert its wording without booting the application.
  @doc "Builds the operator-facing line for a purge result."
  @spec report_line(
          boolean(),
          {:ok, %{records: non_neg_integer(), recovery_sources: non_neg_integer()}}
        ) ::
          String.t()
  def report_line(dry_run?, {:ok, counts}) do
    action = if dry_run?, do: "verified", else: "purged"

    "legacy test data #{action} records=#{counts.records} recovery_sources=#{counts.recovery_sources}"
  end

  @doc "Prints the operator-facing line for a purge result."
  @spec print_report(boolean(), {:ok, map()}) :: :ok
  def print_report(dry_run?, result) do
    Mix.shell().info(report_line(dry_run?, result))
  end

  @doc "Raises the operator-facing refusal for a refused cleanup."
  @spec refuse(term()) :: no_return()
  def refuse(reason) do
    Mix.raise("legacy test data cleanup refused: #{reason}")
  end
end
