defmodule BnestApp.TestRuntimeRoot do
  @moduledoc false

  @marker ".bnest-test-run.json"
  @owner "bnest-test-harness"
  @repo_root Path.expand("../../../..", __DIR__)
  @runs_root Path.join(@repo_root, "data/test/runs")
  @production_root Path.join(@repo_root, "data/prod")

  @type t :: %{path: String.t(), sqlite_path: String.t(), run_id: String.t()}
  @type marker :: %{path: String.t(), run_id: String.t()}

  @spec runs_root() :: String.t()
  def runs_root, do: @runs_root

  @spec sqlite_runs_root() :: String.t()
  def sqlite_runs_root, do: Path.expand("~/bnest/data/test/runs")

  @spec production_root() :: String.t()
  def production_root, do: @production_root

  @spec create!(String.t()) :: t()
  def create!(suite) when is_binary(suite) do
    suite = slug!(suite)
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    run_id = "#{suite}-#{String.downcase(suffix)}"
    path = Path.join(@runs_root, run_id)
    sqlite_path = Path.join(sqlite_runs_root(), run_id)

    with :ok <- validate(path),
         :ok <- validate_sqlite(sqlite_path),
         false <- File.exists?(path),
         false <- File.exists?(sqlite_path),
         :ok <- create_tree(path),
         :ok <- create_sqlite_tree(sqlite_path),
         :ok <- write_marker(path, run_id),
         :ok <- write_marker(sqlite_path, run_id),
         {:ok, _runtime} <- validate(path),
         {:ok, _sqlite_runtime} <- validate_sqlite(sqlite_path) do
      %{path: path, sqlite_path: sqlite_path, run_id: run_id}
    else
      true -> raise ArgumentError, "test runtime already exists"
      {:error, reason} -> raise ArgumentError, "invalid test runtime: #{reason}"
    end
  end

  @spec validate_sqlite(String.t()) :: :ok | {:ok, marker()} | {:error, atom()}
  def validate_sqlite(path) when is_binary(path) do
    expanded = Path.expand(path)
    root = sqlite_runs_root()

    cond do
      expanded == root -> {:error, :shared_root}
      Path.dirname(expanded) != root -> {:error, :outside_test_runs}
      symlink?(expanded) -> {:error, :symlink}
      File.exists?(expanded) -> validate_marker(expanded)
      true -> :ok
    end
  end

  @spec validate(String.t()) :: :ok | {:ok, marker()} | {:error, atom()}
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

  def cleanup(%{path: path, sqlite_path: sqlite_path, run_id: run_id}, processes)
      when is_list(processes) do
    with false <- Enum.any?(processes, &Process.alive?/1),
         {:ok, %{run_id: ^run_id}} <- validate(path),
         {:ok, %{run_id: ^run_id}} <- validate_sqlite(sqlite_path),
         {:ok, _entries} <- File.rm_rf(path),
         {:ok, _entries} <- File.rm_rf(sqlite_path) do
      :ok
    else
      true -> {:error, :processes_running}
      {:error, reason} -> {:error, reason}
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

  defp create_sqlite_tree(path) do
    File.mkdir_p!(path)
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
      "owner" => @owner,
      "pid" => System.pid(),
      "hostname" => hostname()
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

  defp hostname do
    {:ok, hostname} = :inet.gethostname()
    List.to_string(hostname)
  end

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} -> true
      _not_symlink -> false
    end
  end
end
