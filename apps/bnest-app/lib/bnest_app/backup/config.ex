defmodule BnestApp.Backup.Config do
  @moduledoc false

  alias BnestApp.Backup.Location

  @compiled_repository_root Path.expand("../../../../..", __DIR__)

  @spec save(String.t()) :: {:ok, map()} | {:error, atom()}
  def save(directory) do
    now = DateTime.utc_now()

    with {:ok, location} <- Location.ensure(directory, now),
         :ok <- write_config(location.directory) do
      {:ok, location}
    end
  end

  @spec resolve() :: {:ok, map()} | {:error, atom()}
  def resolve do
    directory =
      case File.read(config_path()) do
        {:ok, bytes} -> decode_directory(bytes)
        {:error, :enoent} -> {:ok, default_directory()}
        {:error, _reason} -> {:error, :unavailable}
      end

    with {:ok, directory} <- directory do
      Location.ensure(directory, DateTime.utc_now())
    end
  end

  @spec default_directory() :: String.t()
  def default_directory, do: default_directory(repository_root())

  @doc false
  @spec default_directory(String.t()) :: String.t()
  def default_directory(repository_root), do: Path.join(repository_root, "data/backup")

  @doc false
  @spec document(String.t()) :: map()
  def document(directory),
    do: %{"schemaVersion" => 1, "destinationDirectory" => directory}

  @spec repository_root() :: String.t()
  def repository_root do
    System.get_env("BNEST_REPOSITORY_ROOT") || @compiled_repository_root
  end

  @spec config_path() :: String.t()
  def config_path do
    System.get_env("BNEST_BACKUP_CONFIG") ||
      Path.expand("~/.config/bnest/backup.json")
  end

  defp decode_directory(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{"schemaVersion" => 1, "destinationDirectory" => directory} = config}
      when map_size(config) == 2 and is_binary(directory) ->
        {:ok, directory}

      _invalid ->
        {:error, :invalid_config}
    end
  end

  defp write_config(directory) do
    path = config_path()
    parent = Path.dirname(path)
    File.mkdir_p!(parent)

    if is_nil(System.get_env("BNEST_BACKUP_CONFIG")) do
      File.chmod!(parent, 0o700)
    end

    temporary = path <> ".partial-" <> random_id()

    File.write!(
      temporary,
      Jason.encode!(document(directory))
    )

    File.chmod!(temporary, 0o600)
    File.rename!(temporary, path)
    :ok
  rescue
    File.Error -> {:error, :config_write_failed}
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
