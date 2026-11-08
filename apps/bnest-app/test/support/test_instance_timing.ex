defmodule BnestApp.TestInstance.Timing do
  @moduledoc false

  # Pure statistics for the spawn timing gate. The gate itself lives in the integration layer.

  use Boundary, top_level?: true, check: [in: false, out: false]

  @doc """
  The nearest-rank percentile of `samples`: the smallest sample with at least `percent` percent of
  the samples at or below it. The rank is `ceil(percent * n / 100)`, computed in integers. For
  twenty samples, p50 is the tenth and p95 the nineteenth.
  """
  @spec percentile([number(), ...], 1..100) :: number()
  def percentile([_first | _rest] = samples, percent) when percent in 1..100 do
    sorted = Enum.sort(samples)
    rank = div(percent * length(sorted) + 99, 100)

    Enum.at(sorted, rank - 1)
  end
end
