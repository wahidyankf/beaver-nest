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

    timing_class = if elapsed_ms < 1_000, do: "under-one-second", else: "one-second-or-more"

    Mix.shell().info(
      "argon2id memory_kib=#{options[:memory_kib]} iterations=#{options[:time_cost]} " <>
        "parallelism=#{options[:parallelism]} timing_class=#{timing_class}"
    )
  end
end
