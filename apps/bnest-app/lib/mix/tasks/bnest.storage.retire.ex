defmodule Mix.Tasks.Bnest.Storage.Retire do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Storage

  @shortdoc "Removes verified legacy flat-file and SQLite storage"

  @usage "usage: mix bnest.storage.retire --root <flat-root> --generation <generation> [--dry-run]"

  @impl Mix.Task
  def run(arguments) do
    options = parse!(arguments)
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    flat_root = Path.expand(options.root)

    case Storage.retire(flat_root, options.generation, options.dry_run?) do
      {:ok, count} when is_integer(count) ->
        Mix.shell().info("verified legacy storage ready for retirement (files=#{count})")

      {:ok, _config} ->
        Mix.shell().info("verified legacy storage retired")

      {:error, reason} ->
        Mix.raise("legacy storage retirement refused: #{reason}")
    end
  end

  # The option check runs before the application boots, so a usage refusal
  # never starts an application or touches configuration, a database or a
  # scheduler, and the unit layer can assert its wording without that boot.
  @doc """
  Validates the task's options before the application boots. Raises
  `Mix.Error` with the usage line when `--root` or `--generation` is missing,
  or for an unknown option or a stray argument.
  """
  @spec parse!([String.t()]) :: %{
          root: String.t(),
          generation: String.t(),
          dry_run?: boolean()
        }
  def parse!(arguments) do
    {options, remaining, invalid} =
      OptionParser.parse(arguments,
        strict: [root: :string, generation: :string, dry_run: :boolean]
      )

    if remaining != [] or invalid != [] or is_nil(options[:root]) or
         is_nil(options[:generation]) do
      Mix.raise(@usage)
    end

    %{root: options[:root], generation: options[:generation], dry_run?: options[:dry_run] == true}
  end
end
