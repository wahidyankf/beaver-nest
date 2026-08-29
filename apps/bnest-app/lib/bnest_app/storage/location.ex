defmodule BnestApp.Storage.Location do
  @moduledoc false

  @filename "bnest.sqlite3"

  @spec filename() :: String.t()
  def filename, do: @filename

  @spec default_directory() :: String.t()
  def default_directory, do: Path.expand("~/.config/bnest")

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
