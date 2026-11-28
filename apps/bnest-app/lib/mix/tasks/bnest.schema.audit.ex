defmodule Mix.Tasks.Bnest.Schema.Audit do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Storage

  @shortdoc "Audits only public runtime record structure"

  @usage "usage: mix bnest.schema.audit [--root <runtime-root>]"

  @impl Mix.Task
  def run(arguments) do
    options = parse!(arguments)
    Mix.Task.run("app.config")

    root = options.root || Application.fetch_env!(:bnest_app, :runtime_root)

    case Storage.audit_schema(root) do
      {:ok, results} ->
        print_report(results)
        check!(results)

      {:error, reason} ->
        refuse(reason)
    end
  end

  # The option check runs before the application boots, so a usage refusal
  # never starts an application or touches configuration, a database or a
  # scheduler, and the unit layer can assert its wording without that boot.
  @doc """
  Validates the task's options before the application boots. Raises
  `Mix.Error` with the usage line for an unknown option or a stray argument.
  """
  @spec parse!([String.t()]) :: %{root: String.t() | nil}
  def parse!(arguments) do
    {options, remaining, invalid} = OptionParser.parse(arguments, strict: [root: :string])

    if remaining != [] or invalid != [] do
      Mix.raise(@usage)
    end

    %{root: options[:root]}
  end

  # Each result line is rendered by a pure function, so the unit layer can
  # assert its wording without booting the application.
  @doc "Renders one audit result as the operator-facing `<recordType>:v<n> <result>` line."
  @spec format_result(%{
          required(String.t()) => String.t() | non_neg_integer()
        }) :: String.t()
  def format_result(result) do
    "#{result["recordType"]}:v#{result["schemaVersion"]} #{result["result"]}"
  end

  @doc "Prints the operator-facing line for every audit result."
  @spec print_report([map()]) :: :ok
  def print_report(results) do
    Enum.each(results, fn result -> Mix.shell().info(format_result(result)) end)
  end

  @doc "Raises unless every audit result passed."
  @spec check!([map()]) :: :ok
  def check!(results) do
    if Enum.any?(results, &(&1["result"] != "pass")), do: Mix.raise("schema audit failed")
    :ok
  end

  @doc "Raises the operator-facing refusal for an unreadable audit root."
  @spec refuse(term()) :: no_return()
  def refuse(reason) do
    Mix.raise("schema audit refused: #{reason}")
  end
end
