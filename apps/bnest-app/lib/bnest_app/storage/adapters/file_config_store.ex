defmodule BnestApp.Storage.Adapters.FileConfigStore do
  @moduledoc """
  Keeps the storage pointer as a private JSON file, written atomically through a temporary
  file and a rename.
  """

  @behaviour BnestApp.Storage.Ports.ConfigStore

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Storage.Domain.Location

  @schema_version 1

  @impl true
  def pointer_path do
    System.get_env("BNEST_STORAGE_CONFIG") ||
      Application.get_env(:bnest_app, :storage_config_path) ||
      Path.join(Location.config_directory(), "storage.json")
  end

  @impl true
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

  @impl true
  def resolved_database_path do
    case read() do
      {:ok, config} ->
        Location.database_path(config["databaseDirectory"], config["databaseFilename"])

      {:error, _reason} ->
        Location.database_path(Storage.default_directory())
    end
  end

  @impl true
  def phase do
    case read() do
      {:ok, %{"phase" => "sqlite_primary"}} -> :sqlite_primary
      _other -> :flat_primary
    end
  end

  @impl true
  def database_generation do
    case read() do
      {:ok, config} -> config["databaseGeneration"]
      {:error, _reason} -> nil
    end
  end

  @impl true
  def validate_directory(directory),
    do: Location.validate(directory, %{lstat: &File.lstat/1, stat: &File.stat/1})

  @impl true
  def ensure_default! do
    case read() do
      {:ok, config} ->
        config

      {:error, _reason} ->
        config = %{
          "schemaVersion" => @schema_version,
          "databaseDirectory" => Storage.default_directory(),
          "databaseFilename" => Location.filename(),
          "phase" => "flat_primary",
          "migrationId" => FlatMigration.migration_id()
        }

        write!(config)
        config
    end
  end

  @impl true
  def activate_sqlite_primary! do
    {:ok, config} = read()
    updated = Map.put(config, "phase", "sqlite_primary")
    write!(updated)
    updated
  end

  @impl true
  def relocate!(directory, generation) when is_binary(generation) and generation != "" do
    {:ok, config} = read()
    {:ok, validated} = validate_directory(directory)

    updated =
      config
      |> Map.put("legacyDatabaseDirectory", config["databaseDirectory"])
      |> Map.put("databaseDirectory", validated)
      |> Map.put("databaseGeneration", generation)

    write!(updated)
    updated
  end

  @impl true
  def mark_legacy_retired! do
    {:ok, config} = read()

    updated =
      config
      |> Map.delete("legacyDatabaseDirectory")
      |> Map.put(
        "flatFilesRetiredAt",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

    write!(updated)
    updated
  end

  @impl true
  def restore!(config) when is_map(config) do
    if valid?(config) do
      write!(config)
      config
    else
      raise ArgumentError, "cannot restore an invalid storage pointer"
    end
  end

  @impl true
  def write!(config) do
    path = pointer_path()
    File.mkdir_p!(Path.dirname(path))
    File.chmod!(Path.dirname(path), 0o700)
    temporary = path <> ".tmp-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    File.write!(temporary, Jason.encode!(config))
    File.chmod!(temporary, 0o600)
    File.rename!(temporary, path)
    :ok
  end

  defp valid?(
         %{
           "schemaVersion" => @schema_version,
           "databaseDirectory" => directory,
           "databaseFilename" => filename,
           "phase" => phase,
           "migrationId" => migration_id
         } = config
       )
       when is_binary(directory) and is_binary(filename) and
              phase in ["flat_primary", "sqlite_primary"] and
              is_binary(migration_id) do
    valid_optional_string?(config, "databaseGeneration") and
      valid_optional_string?(config, "legacyDatabaseDirectory") and
      valid_optional_string?(config, "flatFilesRetiredAt")
  end

  defp valid?(_config), do: false

  defp valid_optional_string?(config, key) do
    case Map.fetch(config, key) do
      :error -> true
      {:ok, value} -> is_binary(value) and value != ""
    end
  end
end
