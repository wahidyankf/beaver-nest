defmodule Mix.Tasks.Bnest.Storage.Relocate do
  @moduledoc false

  use Mix.Task

  alias BnestApp.Storage.Location
  alias BnestApp.Storage.Relocation

  @shortdoc "Relocates authoritative SQLite data out of the configuration directory"

  @impl Mix.Task
  def run(arguments) do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    {options, remaining, invalid} =
      OptionParser.parse(arguments, strict: [destination: :string])

    if remaining != [] or invalid != [] do
      Mix.raise("usage: mix bnest.storage.relocate [--destination <directory>]")
    end

    destination = options[:destination] || Location.default_directory()

    case Relocation.run(destination) do
      {:ok, config} ->
        Mix.shell().info("relocation verified generation=#{config["databaseGeneration"]}")

      {:error, reason} ->
        Mix.raise("storage relocation refused: #{reason}")
    end
  end
end
