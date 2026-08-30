defmodule BnestApp.Backup.Location do
  @moduledoc false

  alias BnestApp.Storage.Config, as: StorageConfig

  @marker ".bnest-backup-root.json"
  @scope "bnest-production-backups-v1"
  @repo_root Path.expand("../../../../..", __DIR__)
  @default_directory Path.join(@repo_root, "data/backup")

  @spec ensure(String.t(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def ensure(directory, %DateTime{} = now) do
    with {:ok, directory} <- validate(directory),
         :ok <- create_directory(directory),
         {:ok, marker} <- read_or_create_marker(directory, now) do
      {:ok, %{directory: directory, destination_id: marker["destinationId"]}}
    end
  end

  @spec marker_path(String.t()) :: String.t()
  def marker_path(directory), do: Path.join(directory, @marker)

  @spec read_marker(String.t()) :: {:ok, map()} | {:error, atom()}
  def read_marker(directory) do
    with {:ok, bytes} <- File.read(marker_path(directory)),
         {:ok, marker} <- Jason.decode(bytes),
         true <- valid_marker?(marker) do
      {:ok, marker}
    else
      {:error, :enoent} -> {:error, :absent}
      _invalid -> {:error, :invalid_marker}
    end
  end

  @spec validate(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate(directory) when is_binary(directory) do
    expanded = Path.expand(directory)

    with :ok <- require_absolute(directory),
         :ok <- reject_symlink(expanded),
         :ok <- reject_source_overlap(expanded),
         :ok <- reject_config_overlap(expanded),
         :ok <- restrict_repository_destination(expanded),
         :ok <- require_ignored_default(expanded) do
      {:ok, expanded}
    end
  end

  def validate(_directory), do: {:error, :invalid_directory}

  defp require_absolute(directory) do
    if Path.type(directory) == :absolute, do: :ok, else: {:error, :not_absolute}
  end

  defp reject_symlink(directory) do
    if symlink_in_path?(directory), do: {:error, :symlink}, else: :ok
  end

  defp reject_source_overlap(directory) do
    if overlaps_source?(directory), do: {:error, :source_overlap}, else: :ok
  end

  defp reject_config_overlap(directory) do
    if overlaps_config?(directory), do: {:error, :config_overlap}, else: :ok
  end

  defp restrict_repository_destination(directory) do
    if inside?(directory, @repo_root) and directory != @default_directory,
      do: {:error, :repository_path},
      else: :ok
  end

  defp require_ignored_default(@default_directory) do
    if default_ignored?(), do: :ok, else: {:error, :default_not_ignored}
  end

  defp require_ignored_default(_directory), do: :ok

  defp read_or_create_marker(directory, now) do
    case read_marker(directory) do
      {:ok, marker} ->
        {:ok, marker}

      {:error, :absent} ->
        marker = %{
          "schemaVersion" => 1,
          "ownershipScope" => @scope,
          "destinationId" => random_id(),
          "createdAt" => now |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }

        atomic_write(marker_path(directory), marker)
        {:ok, marker}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_marker?(marker) do
    Map.keys(marker) |> Enum.sort() ==
      Enum.sort(~w(schemaVersion ownershipScope destinationId createdAt)) and
      marker["schemaVersion"] == 1 and marker["ownershipScope"] == @scope and
      is_binary(marker["destinationId"]) and String.length(marker["destinationId"]) == 22 and
      valid_utc?(marker["createdAt"])
  end

  defp create_directory(directory) do
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    :ok
  rescue
    File.Error -> {:error, :unavailable}
  end

  defp atomic_write(path, value) do
    temporary = path <> ".partial-" <> random_id()
    File.write!(temporary, Jason.encode!(value))
    File.chmod!(temporary, 0o600)
    File.rename!(temporary, path)
  end

  defp overlaps_source?(directory) do
    source = StorageConfig.resolved_database_path() |> Path.expand()
    source_directory = Path.dirname(source)
    inside?(directory, source_directory) or inside?(source_directory, directory)
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp valid_utc?(value) do
    match?({:ok, _instant, 0}, DateTime.from_iso8601(value))
  rescue
    FunctionClauseError -> false
  end

  defp overlaps_config?(directory) do
    config_path = BnestApp.Backup.Config.config_path() |> Path.expand()
    inside?(config_path, directory)
  end

  defp default_ignored? do
    case System.cmd("git", ["-C", @repo_root, "check-ignore", "-q", "data/backup"]) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  defp symlink_in_path?(path) do
    path
    |> Path.split()
    |> Enum.scan(fn segment, prefix -> Path.join(prefix, segment) end)
    |> Enum.any?(fn candidate ->
      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(candidate))
    end)
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
