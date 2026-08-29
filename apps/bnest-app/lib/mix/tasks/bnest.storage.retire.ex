defmodule Mix.Tasks.Bnest.Storage.Retire do
  @moduledoc false

  use Mix.Task

  alias BnestApp.Storage.Retirement

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

    result =
      if options[:dry_run] do
        Retirement.verify(Path.expand(options[:root]), options[:generation])
      else
        Retirement.run(Path.expand(options[:root]), options[:generation])
      end

    case result do
      {:ok, count} when is_integer(count) ->
        Mix.shell().info("verified legacy storage ready for retirement (files=#{count})")

      {:ok, _config} ->
        Mix.shell().info("verified legacy storage retired")

      {:error, reason} ->
        Mix.raise("legacy storage retirement refused: #{reason}")
    end
  end
end
