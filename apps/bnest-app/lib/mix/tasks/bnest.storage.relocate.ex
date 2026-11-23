defmodule Mix.Tasks.Bnest.Storage.Relocate do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Storage

  @shortdoc "Relocates authoritative SQLite data out of the configuration directory"

  @usage "usage: mix bnest.storage.relocate [--destination <directory>]"

  @impl Mix.Task
  def run(arguments) do
    options = parse!(arguments)
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    destination = options.destination || Storage.default_directory()

    case Storage.relocate(destination) do
      {:ok, config} ->
        Mix.shell().info("relocation verified generation=#{config["databaseGeneration"]}")

      {:error, reason} ->
        Mix.raise("storage relocation refused: #{reason}")
    end
  end

  # The option check runs before the application boots, so a usage refusal
  # never starts an application or touches configuration, a database or a
  # scheduler, and the unit layer can assert its wording without that boot.
  @doc """
  Validates the task's options before the application boots. Raises
  `Mix.Error` with the usage line for an unknown option or a stray argument.
  """
  @spec parse!([String.t()]) :: %{destination: String.t() | nil}
  def parse!(arguments) do
    {options, remaining, invalid} =
      OptionParser.parse(arguments, strict: [destination: :string])

    if remaining != [] or invalid != [] do
      Mix.raise(@usage)
    end

    %{destination: options[:destination]}
  end
end
