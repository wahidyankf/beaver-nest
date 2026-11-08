defmodule BnestApp.TestInstance.TimingTest do
  use ExUnit.Case, async: true

  alias BnestApp.TestInstance.Timing

  test "takes the nearest-rank percentile, so twenty samples give the tenth and nineteenth" do
    samples = Enum.shuffle(1..20)

    assert Timing.percentile(samples, 50) == 10
    assert Timing.percentile(samples, 95) == 19
    assert Timing.percentile(samples, 100) == 20
  end

  test "rounds the rank up, so the 95th percentile of ten samples is the largest" do
    samples = Enum.shuffle(1..10)

    assert Timing.percentile(samples, 50) == 5
    assert Timing.percentile(samples, 95) == 10
  end

  test "a single sample is every percentile" do
    assert Timing.percentile([7.5], 50) == 7.5
    assert Timing.percentile([7.5], 95) == 7.5
  end
end
