defmodule BnestApp.Storage.Location do
  @moduledoc false

  @filename "bnest.sqlite3"

  @spec filename() :: String.t()
  def filename, do: @filename

  @spec database_path(String.t(), String.t()) :: String.t()
  def database_path(directory, filename \\ @filename)
      when is_binary(directory) and is_binary(filename),
      do: Path.join(directory, filename)

  @spec config_directory() :: String.t()
  def config_directory, do: Path.expand("~/.config/bnest")

  @spec production_data_directory() :: String.t()
  def production_data_directory, do: production_data_directory(Path.expand("~"))

  @spec production_data_directory(String.t()) :: String.t()
  def production_data_directory(home_directory) when is_binary(home_directory),
    do: Path.join(home_directory, "bnest/data/prod")

  @spec test_data_directory(String.t()) :: String.t()
  def test_data_directory(run_id) when is_binary(run_id) and run_id != "" do
    Path.expand("~/bnest/data/test/runs/#{run_id}")
  end

  def test_data_directory(_run_id), do: raise(ArgumentError, "BNEST_TEST_RUN_ID is required")

  @spec default_directory() :: String.t()
  def default_directory do
    case Application.get_env(:bnest_app, :storage_profile, :production) do
      :production -> production_data_directory()
      {:test, run_id} -> test_data_directory(run_id)
    end
  end

  @spec validate(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate(directory) do
    filesystem = %{lstat: &File.lstat/1, stat: &File.stat/1}

    validate(directory, filesystem)
  end

  @doc false
  @spec validate(String.t(), map()) :: {:ok, String.t()} | {:error, atom()}
  def validate(directory, filesystem) when is_binary(directory) do
    expanded = Path.expand(directory)

    cond do
      not absolute_input?(directory) -> {:error, :not_absolute}
      symlink_component?(expanded, filesystem) -> {:error, :symlink}
      overlaps_boundary?(expanded) -> {:error, :unsafe_location}
      unsafe_world_writable_location?(expanded, filesystem) -> {:error, :world_writable}
      true -> {:ok, expanded}
    end
  end

  def validate(_directory, _filesystem), do: {:error, :not_absolute}

  defp absolute_input?(directory),
    do: String.starts_with?(directory, "/") or String.starts_with?(directory, "~")

  defp symlink_component?(path, %{lstat: lstat}) do
    Enum.any?([path, Path.dirname(path)], fn candidate ->
      match?({:ok, %{type: :symlink}}, lstat.(candidate))
    end)
  end

  defp overlaps_boundary?(path) do
    repository_root = Path.expand("../../../../..", __DIR__)

    Enum.any?(
      [
        repository_root,
        Path.join(repository_root, "data"),
        Path.join(repository_root, "apps")
      ],
      fn boundary -> path == boundary or String.starts_with?(path, boundary <> "/") end
    )
  end

  defp unsafe_world_writable_location?(path, filesystem),
    do:
      world_writable?(path, filesystem) or
        non_sticky_world_writable?(Path.dirname(path), filesystem)

  defp world_writable?(path, filesystem),
    do: mode_matches?(path, filesystem, &(Bitwise.band(&1, 0o002) != 0))

  defp non_sticky_world_writable?(path, filesystem) do
    mode_matches?(path, filesystem, fn mode ->
      Bitwise.band(mode, 0o002) != 0 and Bitwise.band(mode, 0o1000) == 0
    end)
  end

  defp mode_matches?(path, %{stat: stat}, predicate) do
    case stat.(path) do
      {:ok, %{mode: mode}} -> predicate.(mode)
      {:error, _reason} -> false
    end
  end
end
