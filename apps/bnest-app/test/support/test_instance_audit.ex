defmodule BnestApp.TestInstance.Audit do
  @moduledoc false

  # The end-of-run verdict of ADR 001 (section 3). The integration run gathers three facts: the instance
  # directories still on disk, the instance that is still current, and whether the run base is data-free.
  # `verdict/4` turns them into a result that names every leftover, so the run can fail with all of them. It
  # is pure: nothing is read or removed here.
  #
  # `legacy_roots` are base directories that the shared-base scenarios still write to. Their data is reported as
  # a warning, not a failure, until those scenarios move to fresh databases (T9b). Nothing else is excused: an
  # instance leftover, the current instance and any other base data always fail.

  use Boundary, top_level?: true, check: [in: false, out: false]

  @type base :: :ok | {:error, [String.t()]}

  @doc """
  `{:ok, warnings}` when no failure is left, with one warning per base path under a legacy root. Otherwise
  `{:error, reasons}`, one reason per failing leftover.
  """
  @spec verdict([String.t()], map() | nil, base(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, [String.t()]}
  def verdict(directories, current, base, legacy_roots \\ []) do
    {legacy, strict} = split_base(base, legacy_roots)

    errors =
      Enum.map(directories, &"instance directory left behind: #{&1}") ++
        current_reason(current) ++ Enum.map(strict, &"run base is not data-free: #{&1}")

    warnings = Enum.map(legacy, &"legacy shared run data, removed by T9b: #{&1}")

    if errors == [], do: {:ok, warnings}, else: {:error, errors}
  end

  defp current_reason(nil), do: []

  defp current_reason(%{instance_id: instance_id}),
    do: ["test instance still current at end of run: #{instance_id}"]

  defp split_base(:ok, _legacy_roots), do: {[], []}

  defp split_base({:error, paths}, legacy_roots) do
    # A root names a directory (its children match) or one exact file (the shared database and its sidecars).
    Enum.split_with(paths, fn path ->
      Enum.any?(legacy_roots, &(path == &1 or String.starts_with?(path, &1 <> "/")))
    end)
  end
end
