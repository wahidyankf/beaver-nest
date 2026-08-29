defmodule BnestApp.Storage.Config do
  @moduledoc false

  alias BnestApp.Storage.Location

  @schema_version 1

  @spec pointer_path() :: String.t()
  def pointer_path do
    System.get_env("BNEST_STORAGE_CONFIG") ||
      Path.join(Location.default_directory(), "storage.json")
  end

  @spec read() :: {:ok, map()} | {:error, :absent | :invalid}
  def read do
    with {:ok, bytes} <- File.read(pointer_path()),
         {:ok, config} <- Jason.decode(bytes),
         true <- valid?(config) do
      {:ok, config}
    else
      {:error, :enoent} -> {:error, :absent}
      _invalid -> {:error, :invalid}
    end
  end

  @spec resolved_database_path() :: String.t()
  def resolved_database_path do
    case read() do
      {:ok, config} -> Path.join(config["databaseDirectory"], config["databaseFilename"])
      {:error, _reason} -> Path.join(Location.default_directory(), Location.filename())
    end
  end

  @spec phase() :: :flat_primary | :sqlite_primary
  def phase do
    case read() do
      {:ok, %{"phase" => "sqlite_primary"}} -> :sqlite_primary
      _other -> :flat_primary
    end
  end

  @spec persist_directory(String.t()) :: {:ok, map()} | {:error, atom()}
  def persist_directory(directory) do
    with {:error, :absent} <- guard_immutable(),
         {:ok, validated} <- Location.validate(directory) do
      config = %{
        "schemaVersion" => @schema_version,
        "databaseDirectory" => validated,
        "databaseFilename" => Location.filename(),
        "phase" => "flat_primary",
        "migrationId" => "flat-files-v1-to-sqlite-v1"
      }

      write!(config)
      {:ok, config}
    else
      {:ok, _existing} -> {:error, :immutable}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ensure_default!() :: map()
  def ensure_default! do
    case read() do
      {:ok, config} ->
        config

      {:error, _reason} ->
        config = %{
          "schemaVersion" => @schema_version,
          "databaseDirectory" => Location.default_directory(),
          "databaseFilename" => Location.filename(),
          "phase" => "flat_primary",
          "migrationId" => "flat-files-v1-to-sqlite-v1"
        }

        write!(config)
        config
    end
  end

  @spec activate_sqlite_primary!() :: map()
  def activate_sqlite_primary! do
    {:ok, config} = read()
    updated = Map.put(config, "phase", "sqlite_primary")
    write!(updated)
    updated
  end

  defp guard_immutable do
    case read() do
      {:ok, _config} -> {:ok, :exists}
      {:error, :absent} -> {:error, :absent}
      {:error, :invalid} -> {:error, :invalid}
    end
  end

  defp valid?(%{
         "schemaVersion" => @schema_version,
         "databaseDirectory" => directory,
         "databaseFilename" => filename,
         "phase" => phase,
         "migrationId" => migration_id
       })
       when is_binary(directory) and is_binary(filename) and
              phase in ["flat_primary", "sqlite_primary"] and
              is_binary(migration_id),
       do: true

  defp valid?(_config), do: false

  defp write!(config) do
    path = pointer_path()
    File.mkdir_p!(Path.dirname(path))
    File.chmod!(Path.dirname(path), 0o700)
    temporary = path <> ".tmp-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    File.write!(temporary, Jason.encode!(config))
    File.chmod!(temporary, 0o600)
    File.rename!(temporary, path)
    :ok
  end
end
