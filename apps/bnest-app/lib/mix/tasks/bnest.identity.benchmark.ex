defmodule Mix.Tasks.Bnest.Identity.Benchmark do
  @moduledoc false

  use Mix.Task

  @shortdoc "Measures the configured Argon2id work factor without printing secrets"

  @impl Mix.Task
  def run(_arguments) do
    options = Application.fetch_env!(:bnest_app, :argon2)
    started = System.monotonic_time()
    verifier = Argon2.hash_pwd_salt(:crypto.strong_rand_bytes(32))

    elapsed_ms =
      System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

    unless String.starts_with?(verifier, "$argon2id$") do
      Mix.raise("configured password hasher did not produce Argon2id")
    end

    timing_class = if elapsed_ms < 1_000, do: "under-one-second", else: "one-second-or-more"

    Mix.shell().info(
      "argon2id memory_kib=#{options[:memory_kib]} iterations=#{options[:time_cost]} " <>
        "parallelism=#{options[:parallelism]} timing_class=#{timing_class}"
    )
  end
end
