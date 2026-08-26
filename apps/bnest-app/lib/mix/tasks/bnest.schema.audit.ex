defmodule Mix.Tasks.Bnest.Schema.Audit do
  @moduledoc false

  use Mix.Task

  alias BnestApp.DataRepository.Schema

  @shortdoc "Audits only public runtime record structure"

  @impl Mix.Task
  def run(arguments) do
    Mix.Task.run("app.config")
    {options, remaining, invalid} = OptionParser.parse(arguments, strict: [root: :string])

    if remaining != [] or invalid != [] do
      Mix.raise("usage: mix bnest.schema.audit [--root <runtime-root>]")
    end

    root = options[:root] || Application.fetch_env!(:bnest_app, :runtime_root)

    case Schema.audit_root(root) do
      {:ok, results} ->
        Enum.each(results, fn result ->
          Mix.shell().info(
            "#{result["recordType"]}:v#{result["schemaVersion"]} #{result["result"]}"
          )
        end)

        if Enum.any?(results, &(&1["result"] != "pass")), do: Mix.raise("schema audit failed")

      {:error, reason} ->
        Mix.raise("schema audit refused: #{reason}")
    end
  end
end
