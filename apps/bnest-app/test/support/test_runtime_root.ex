defmodule BnestApp.TestRuntimeRoot do
  @moduledoc false

  @marker ".bnest-test-run.json"
  @owner "bnest-test-harness"
  @repo_root Path.expand("../../../..", __DIR__)
  @runs_root Path.join(@repo_root, "data/test/runs")
  @production_root Path.join(@repo_root, "data/prod")

  @type t :: %{path: String.t(), run_id: String.t()}

  @spec runs_root() :: String.t()
  def runs_root, do: @runs_root

  @spec production_root() :: String.t()
  def production_root, do: @production_root

  @spec create!(String.t()) :: t()
  def create!(suite) when is_binary(suite) do
    suite = slug!(suite)
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    run_id = "#{suite}-#{String.downcase(suffix)}"
    path = Path.join(@runs_root, run_id)

    with :ok <- validate(path),
         false <- File.exists?(path),
         :ok <- create_tree(path),
         :ok <- write_marker(path, run_id),
         {:ok, _runtime} <- validate(path) do
      %{path: path, run_id: run_id}
    else
      true -> raise ArgumentError, "test runtime already exists"
      {:error, reason} -> raise ArgumentError, "invalid test runtime: #{reason}"
    end
  end

  @spec validate(String.t()) :: :ok | {:ok, t()} | {:error, atom()}
  def validate(path) when is_binary(path) do
    expanded = Path.expand(path)

    cond do
      expanded == @production_root or inside?(expanded, @production_root) ->
        {:error, :production_root}

      expanded == @runs_root ->
        {:error, :shared_root}

      Path.dirname(expanded) != @runs_root ->
        {:error, :outside_test_runs}

      symlink?(expanded) ->
        {:error, :symlink}

      File.exists?(expanded) ->
        validate_marker(expanded)

      true ->
        :ok
    end
  end

  @spec cleanup(t(), [pid()]) :: :ok | {:error, atom()}
  def cleanup(runtime, processes \\ [])

  def cleanup(%{path: path, run_id: run_id}, processes) when is_list(processes) do
    with false <- Enum.any?(processes, &Process.alive?/1),
         {:ok, %{run_id: ^run_id}} <- validate(path),
         {:ok, _entries} <- File.rm_rf(path) do
      :ok
    else
      true -> {:error, :processes_running}
      {:error, reason} -> {:error, reason}
      {:error, _reason, _file} -> {:error, :cleanup_failed}
    end
  end

  @spec cleanup!(t()) :: :ok
  def cleanup!(runtime) do
    case cleanup(runtime) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "test runtime cleanup refused: #{reason}"
    end
  end

  defp create_tree(path) do
    ["general", "apps/beaver-nest", "system", "users"]
    |> Enum.each(fn relative -> File.mkdir_p!(Path.join(path, relative)) end)

    :ok
  rescue
    File.Error -> {:error, :create_failed}
  end

  defp write_marker(path, run_id) do
    marker = %{
      "schemaVersion" => 1,
      "recordType" => "bnest-test-run",
      "runId" => run_id,
      "createdAt" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "owner" => @owner
    }

    File.write!(Path.join(path, @marker), Jason.encode!(marker))
    :ok
  rescue
    File.Error -> {:error, :marker_write_failed}
  end

  defp validate_marker(path) do
    marker_path = Path.join(path, @marker)
    run_id = Path.basename(path)

    with {:ok, bytes} <- File.read(marker_path),
         {:ok,
          %{
            "schemaVersion" => 1,
            "recordType" => "bnest-test-run",
            "runId" => ^run_id,
            "createdAt" => created_at,
            "owner" => @owner
          }} <- Jason.decode(bytes),
         {:ok, _timestamp, 0} <- DateTime.from_iso8601(created_at) do
      {:ok, %{path: path, run_id: run_id}}
    else
      _invalid -> {:error, :invalid_marker}
    end
  end

  defp slug!(value) do
    slug =
      value
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9-]+/u, "-")
      |> String.trim("-")

    if slug == "", do: raise(ArgumentError, "test suite name is empty"), else: slug
  end

  defp inside?(path, root), do: String.starts_with?(path, root <> "/")

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} -> true
      _not_symlink -> false
    end
  end
end
