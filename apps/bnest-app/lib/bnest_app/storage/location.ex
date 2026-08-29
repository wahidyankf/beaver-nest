defmodule BnestApp.Storage.Location do
  @moduledoc false

  @filename "bnest.sqlite3"

  @spec filename() :: String.t()
  def filename, do: @filename

  @spec config_directory() :: String.t()
  def config_directory, do: Path.expand("~/.config/bnest")

  @spec production_data_directory() :: String.t()
  def production_data_directory, do: Path.expand("~/bnest/data/prod")

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
  def validate(directory) when is_binary(directory) do
    expanded = Path.expand(directory)

    cond do
      not absolute_input?(directory) -> {:error, :not_absolute}
      symlink_component?(expanded) -> {:error, :symlink}
      overlaps_boundary?(expanded) -> {:error, :unsafe_location}
      world_writable_parent?(expanded) -> {:error, :world_writable}
      true -> {:ok, expanded}
    end
  end

  def validate(_directory), do: {:error, :not_absolute}

  defp absolute_input?(directory),
    do: String.starts_with?(directory, "/") or String.starts_with?(directory, "~")

  defp symlink_component?(path) do
    Enum.any?([path, Path.dirname(path)], fn candidate ->
      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(candidate))
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

  defp world_writable_parent?(path) do
    case File.stat(Path.dirname(path)) do
      {:ok, %File.Stat{mode: mode}} -> Bitwise.band(mode, 0o002) != 0
      {:error, _reason} -> false
    end
  end
end
