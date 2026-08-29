defmodule Mix.Tasks.Bnest.Storage.PurgeTestData do
  @moduledoc false

  use Mix.Task

  alias BnestApp.Storage.TestDataCleanup

  @shortdoc "Removes verified legacy test identities from production SQLite"

  @impl Mix.Task
  def run(arguments) do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    {options, remaining, invalid} =
      OptionParser.parse(arguments, strict: [generation: :string, dry_run: :boolean])

    if remaining != [] or invalid != [] or is_nil(options[:generation]) do
      Mix.raise("usage: mix bnest.storage.purge_test_data --generation <generation> [--dry-run]")
    end

    result =
      if options[:dry_run] do
        TestDataCleanup.verify(options[:generation])
      else
        TestDataCleanup.run(options[:generation])
      end

    case result do
      {:ok, counts} ->
        action = if options[:dry_run], do: "verified", else: "purged"

        Mix.shell().info(
          "legacy test data #{action} records=#{counts.records} recovery_sources=#{counts.recovery_sources}"
        )

      {:error, reason} ->
        Mix.raise("legacy test data cleanup refused: #{reason}")
    end
  end
end
