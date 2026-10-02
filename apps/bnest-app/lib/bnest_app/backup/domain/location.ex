defmodule BnestApp.Backup.Domain.Location do
  @moduledoc """
  Where backups may go. A destination is an absolute directory that overlaps neither the
  live database's directory nor the backup configuration, and lies outside the repository
  unless it is the repository's own default, `data/backup`, which the repository must ignore.
  A destination is owned through its marker, which names its destination ID; the
  configuration names only the destination directory.
  """

  @marker ".bnest-backup-root.json"
  @scope "bnest-production-backups-v1"
  @default_relative_path "data/backup"

  @doc "The repository-relative path of the default destination."
  @spec default_relative_path() :: String.t()
  def default_relative_path, do: @default_relative_path

  @doc "The default destination inside `repository_root`."
  @spec default_directory(String.t()) :: String.t()
  def default_directory(repository_root), do: Path.join(repository_root, @default_relative_path)

  @doc "The path of the ownership marker in `directory`."
  @spec marker_path(String.t()) :: String.t()
  def marker_path(directory), do: Path.join(directory, @marker)

  @doc "The configuration document naming `directory` as the destination."
  @spec config_document(String.t()) :: map()
  def config_document(directory),
    do: %{"schemaVersion" => 1, "destinationDirectory" => directory}

  @doc "The destination directory a stored configuration document names."
  @spec configured_directory(term()) :: {:ok, String.t()} | {:error, :invalid_config}
  def configured_directory(%{"schemaVersion" => 1, "destinationDirectory" => directory} = config)
      when map_size(config) == 2 and is_binary(directory),
      do: {:ok, directory}

  def configured_directory(_invalid), do: {:error, :invalid_config}

  @doc "`directory` expanded, when it is absolute."
  @spec absolute(term()) :: {:ok, String.t()} | {:error, :not_absolute | :invalid_directory}
  def absolute(directory) when is_binary(directory) do
    if Path.type(directory) == :absolute,
      do: {:ok, Path.expand(directory)},
      else: {:error, :not_absolute}
  end

  def absolute(_directory), do: {:error, :invalid_directory}

  @doc "Refuses a destination inside, or containing, the directory of the live database."
  @spec outside_source(String.t(), String.t()) :: :ok | {:error, :source_overlap}
  def outside_source(directory, source_path) do
    source_directory = source_path |> Path.expand() |> Path.dirname()

    if inside?(directory, source_directory) or inside?(source_directory, directory),
      do: {:error, :source_overlap},
      else: :ok
  end

  @doc "Refuses a destination that contains the backup configuration."
  @spec outside_config(String.t(), String.t()) :: :ok | {:error, :config_overlap}
  def outside_config(directory, config_path) do
    if inside?(Path.expand(config_path), directory), do: {:error, :config_overlap}, else: :ok
  end

  @doc "Refuses a destination inside `repository_root` other than its default."
  @spec repository_placement(String.t(), String.t()) :: :ok | {:error, :repository_path}
  def repository_placement(directory, repository_root) do
    if inside?(directory, repository_root) and not default?(directory, repository_root),
      do: {:error, :repository_path},
      else: :ok
  end

  @doc "Whether `directory` is the default destination of `repository_root`."
  @spec default?(String.t(), String.t()) :: boolean()
  def default?(directory, repository_root),
    do: directory == default_directory(repository_root)

  @doc "A new destination's marker, naming `destination_id`, created at `now`."
  @spec new_marker(String.t(), DateTime.t()) :: map()
  def new_marker(destination_id, %DateTime{} = now) do
    %{
      "schemaVersion" => 1,
      "ownershipScope" => @scope,
      "destinationId" => destination_id,
      "createdAt" => now |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  @doc "Whether a stored marker is a valid ownership marker of this application."
  @spec valid_marker?(map()) :: boolean()
  def valid_marker?(marker) do
    Map.keys(marker) |> Enum.sort() ==
      Enum.sort(~w(schemaVersion ownershipScope destinationId createdAt)) and
      marker["schemaVersion"] == 1 and marker["ownershipScope"] == @scope and
      is_binary(marker["destinationId"]) and String.length(marker["destinationId"]) == 22 and
      valid_utc?(marker["createdAt"])
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp valid_utc?(value) do
    match?({:ok, _instant, 0}, DateTime.from_iso8601(value))
  rescue
    FunctionClauseError -> false
  end
end
