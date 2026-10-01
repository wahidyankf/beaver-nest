defmodule Mix.Tasks.Bnest.Storage.Retire do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Storage

  @shortdoc "Removes verified legacy flat-file and SQLite storage"

  @impl Mix.Task
  def run(arguments) do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    {options, remaining, invalid} =
      OptionParser.parse(arguments,
        strict: [root: :string, generation: :string, dry_run: :boolean]
      )

    if remaining != [] or invalid != [] or is_nil(options[:root]) or
         is_nil(options[:generation]) do
      Mix.raise(
        "usage: mix bnest.storage.retire --root <flat-root> --generation <generation> [--dry-run]"
      )
    end

    flat_root = Path.expand(options[:root])

    case Storage.retire(flat_root, options[:generation], options[:dry_run] == true) do
      {:ok, count} when is_integer(count) ->
        Mix.shell().info("verified legacy storage ready for retirement (files=#{count})")

      {:ok, _config} ->
        Mix.shell().info("verified legacy storage retired")

      {:error, reason} ->
        Mix.raise("legacy storage retirement refused: #{reason}")
    end
  end
end
