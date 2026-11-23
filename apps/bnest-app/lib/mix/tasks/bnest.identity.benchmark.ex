defmodule Mix.Tasks.Bnest.Identity.Benchmark do
  @moduledoc false

  use Mix.Task
  use Boundary, classify_to: BnestAppCli

  alias BnestApp.Identity

  @shortdoc "Measures the configured Argon2id work factor without printing secrets"

  @impl Mix.Task
  def run(_arguments) do
    options = Application.fetch_env!(:bnest_app, :argon2)

    elapsed_ms =
      case Identity.benchmark_hasher() do
        {:ok, elapsed_ms} ->
          elapsed_ms

        {:error, _not_argon2id} ->
          Mix.raise("configured password hasher did not produce Argon2id")
      end

    Mix.shell().info(report_line(options, elapsed_ms))
  end

  # The timing class and the printed line are pure over the configured cost
  # and the measured time, so the unit layer can assert their wording without
  # booting the application or timing a real hash.
  @doc "Classes a hash timing as the operator-facing `under-one-second` or `one-second-or-more`."
  @spec timing_class(non_neg_integer()) :: String.t()
  def timing_class(elapsed_ms) when is_integer(elapsed_ms) and elapsed_ms >= 0 do
    if elapsed_ms < 1_000, do: "under-one-second", else: "one-second-or-more"
  end

  @doc "Builds the operator-facing benchmark line, which carries no password or hash."
  @spec report_line(keyword(), non_neg_integer()) :: String.t()
  def report_line(options, elapsed_ms) do
    "argon2id memory_kib=#{options[:memory_kib]} iterations=#{options[:time_cost]} " <>
      "parallelism=#{options[:parallelism]} timing_class=#{timing_class(elapsed_ms)}"
  end
end
