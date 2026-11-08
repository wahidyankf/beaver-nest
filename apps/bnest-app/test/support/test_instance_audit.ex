defmodule BnestApp.TestInstance.Audit do
  @moduledoc false

  # The end-of-run verdict of ADR 001 (section 3). The integration run gathers four facts: the instance
  # directories still on disk, the instance that is still current, whether the run base is data-free, and
  # which run-root files hold a run secret. `verdict/4` turns them into a result that names every leftover, so
  # the run can fail with all of them. It is pure: nothing is read or removed here. The caller reads the files
  # and passes their bytes to `secret_leaks/2`.
  #
  # There is no legacy allowance. Every integration scenario runs on its own test instance, so the run base holds
  # no account, user, or database, and any path under it is a failure.

  use Boundary, top_level?: true, check: [in: false, out: false]

  @type base :: :ok | {:error, [String.t()]}

  @doc """
  `:ok` when nothing is left behind. Otherwise `{:error, reasons}`, one reason per failing leftover. `leaks` are
  the reasons `secret_leaks/2` returned.
  """
  @spec verdict([String.t()], map() | nil, base(), [String.t()]) :: :ok | {:error, [String.t()]}
  def verdict(directories, current, base, leaks \\ []) do
    errors =
      Enum.map(directories, &"instance directory left behind: #{&1}") ++
        current_reason(current) ++ base_reasons(base) ++ leaks

    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc """
  One reason for each file whose bytes hold one of the `secrets`, so the run fails if a run secret was written to
  disk. `files` is `[{path, bytes}]`. An empty secret matches nothing. A reason names the file and never the secret.
  """
  @spec secret_leaks([{String.t(), binary()}], [String.t()]) :: [String.t()]
  def secret_leaks(files, secrets) do
    secrets = Enum.reject(secrets, &(&1 == ""))

    for {path, bytes} <- files,
        Enum.any?(secrets, &(:binary.match(bytes, &1) != :nomatch)),
        do: "run secret written to a run-root file: #{path}"
  end

  defp current_reason(nil), do: []

  defp current_reason(%{instance_id: instance_id}),
    do: ["test instance still current at end of run: #{instance_id}"]

  defp base_reasons(:ok), do: []

  defp base_reasons({:error, paths}), do: Enum.map(paths, &"run base is not data-free: #{&1}")
end
