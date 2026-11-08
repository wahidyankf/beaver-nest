defmodule BnestApp.TestInstance.SpawnTimingTest do
  # The timing gate of ADR 001 section 4: twenty spawns, with the p50 and p95 of the spawn time
  # recorded and printed. Only `spawn!/2` is timed; the drop that makes room for the next spawn is
  # not. The gate fails above a p95 of 500 ms. A failed gate is reported, never retried.
  use ExUnit.Case, async: false

  @moduletag :test_instance

  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Timing

  @samples 20
  @p95_limit_ms 500

  setup do
    run = TestInstance.application_run!()
    assert TestInstance.state() == nil

    on_exit(fn ->
      case TestInstance.state() do
        nil -> :ok
        instance -> TestInstance.drop!(instance)
      end
    end)

    %{run: run}
  end

  test "twenty spawns keep the p95 spawn time at or under 500 ms", %{run: run} do
    spawn_ms =
      for _sample <- 1..@samples do
        {micros, instance} = :timer.tc(fn -> TestInstance.spawn!(run) end)
        assert :ok = TestInstance.drop!(instance)
        micros / 1000
      end

    p50 = Timing.percentile(spawn_ms, 50)
    p95 = Timing.percentile(spawn_ms, 95)

    IO.puts(
      "spawn timing over #{@samples} spawns: p50=#{format(p50)} ms p95=#{format(p95)} ms " <>
        "max=#{format(Enum.max(spawn_ms))} ms loadavg=#{load_average()}"
    )

    assert p95 <= @p95_limit_ms,
           "p95 spawn time #{format(p95)} ms is above the #{@p95_limit_ms} ms gate"
  end

  defp format(ms), do: :erlang.float_to_binary(ms / 1, decimals: 1)

  defp load_average do
    case File.read("/proc/loadavg") do
      {:ok, text} -> text |> String.split(" ") |> Enum.take(3) |> Enum.join(" ")
      {:error, _reason} -> "unavailable"
    end
  end
end
