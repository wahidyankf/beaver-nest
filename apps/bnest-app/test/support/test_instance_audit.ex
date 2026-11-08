defmodule BnestApp.TestInstance.Audit do
  @moduledoc false

  # The end-of-run verdict of ADR 001 (section 3). The integration run gathers three facts: the instance
  # directories still on disk, the instance that is still current, and whether the run base is data-free.
  # `verdict/3` turns them into a result that names every leftover, so the run can fail with all of them. It
  # is pure: nothing is read or removed here.
  #
  # There is no legacy allowance. Every integration scenario runs on its own test instance, so the run base holds
  # no account, user, or database, and any path under it is a failure.

  use Boundary, top_level?: true, check: [in: false, out: false]

  @type base :: :ok | {:error, [String.t()]}

  @doc "`:ok` when nothing is left behind. Otherwise `{:error, reasons}`, one reason per failing leftover."
  @spec verdict([String.t()], map() | nil, base()) :: :ok | {:error, [String.t()]}
  def verdict(directories, current, base) do
    errors =
      Enum.map(directories, &"instance directory left behind: #{&1}") ++
        current_reason(current) ++ base_reasons(base)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp current_reason(nil), do: []

  defp current_reason(%{instance_id: instance_id}),
    do: ["test instance still current at end of run: #{instance_id}"]

  defp base_reasons(:ok), do: []

  defp base_reasons({:error, paths}), do: Enum.map(paths, &"run base is not data-free: #{&1}")
end
