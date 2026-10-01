defmodule BnestApp.Test.InMemory.StoragePorts do
  @moduledoc """
  In-memory doubles for the Storage ports other than the record backend. They share one
  agent, started by `install/1` and linked to the test, which holds their state and the
  calls they receive in order. The configuration they replace is application-wide, so
  only one non-async test may install them at a time.
  """

  alias BnestApp.Test.InMemory.StoragePorts.{ConfigStore, DatabaseLifecycle, Lock, Maintenance}

  @doc """
  Points `config :bnest_app, BnestApp.Storage` at the doubles for the rest of the test and
  returns the previous configuration for `restore/1`.
  """
  @spec install(keyword()) :: keyword()
  def install(state \\ []) do
    previous = Application.fetch_env!(:bnest_app, BnestApp.Storage)

    {:ok, _agent} =
      Agent.start_link(fn -> %{calls: [], values: Map.new(state)} end, name: __MODULE__)

    Application.put_env(
      :bnest_app,
      BnestApp.Storage,
      Keyword.merge(previous,
        config_store: ConfigStore,
        lock: Lock,
        database_lifecycle: DatabaseLifecycle,
        maintenance: Maintenance
      )
    )

    previous
  end

  @spec restore(keyword()) :: :ok
  def restore(previous), do: Application.put_env(:bnest_app, BnestApp.Storage, previous)

  @doc "The calls the doubles received, oldest first."
  @spec calls() :: [term()]
  def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))

  @doc false
  def record(call), do: Agent.update(__MODULE__, &%{&1 | calls: [call | &1.calls]})

  @doc false
  def get(key, default), do: Agent.get(__MODULE__, &Map.get(&1.values, key, default))

  @doc false
  def put(key, value), do: Agent.update(__MODULE__, &put_in(&1.values[key], value))
end

defmodule BnestApp.Test.InMemory.StoragePorts.ConfigStore do
  @moduledoc false

  @behaviour BnestApp.Storage.Ports.ConfigStore

  alias BnestApp.Storage.Domain.Location
  alias BnestApp.Test.InMemory.StoragePorts

  @default_directory "/in-memory/bnest/data"

  @impl true
  def pointer_path, do: "/in-memory/config/storage.json"

  @impl true
  def read do
    case StoragePorts.get(:config, nil) do
      nil -> {:error, :absent}
      :invalid -> {:error, :invalid}
      config -> {:ok, config}
    end
  end

  @impl true
  def write!(config) do
    StoragePorts.record({:write_config, config})
    StoragePorts.put(:config, config)
    :ok
  end

  @impl true
  def resolved_database_path do
    case read() do
      {:ok, config} ->
        Location.database_path(config["databaseDirectory"], config["databaseFilename"])

      {:error, _reason} ->
        Location.database_path(@default_directory)
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

  # No candidate path exists, so only the path rules decide.
  @impl true
  def validate_directory(directory),
    do:
      Location.validate(directory, %{
        lstat: fn _ -> {:error, :enoent} end,
        stat: fn _ -> {:error, :enoent} end
      })

  @impl true
  def ensure_default! do
    case read() do
      {:ok, config} ->
        config

      {:error, _reason} ->
        config = %{
          "schemaVersion" => 1,
          "databaseDirectory" => @default_directory,
          "databaseFilename" => Location.filename(),
          "phase" => "flat_primary",
          "migrationId" => "flat-files-v1-to-sqlite-v1"
        }

        write!(config)
        config
    end
  end

  @impl true
  def activate_sqlite_primary!, do: update!(&Map.put(&1, "phase", "sqlite_primary"))

  @impl true
  def relocate!(directory, generation),
    do:
      update!(
        &Map.merge(&1, %{"databaseDirectory" => directory, "databaseGeneration" => generation})
      )

  # Like the production adapter, retirement drops the legacy directory and stamps the time.
  @impl true
  def mark_legacy_retired!,
    do:
      update!(
        &(&1
          |> Map.delete("legacyDatabaseDirectory")
          |> Map.put("flatFilesRetiredAt", BnestApp.Storage.now()))
      )

  @impl true
  def restore!(config) do
    write!(config)
    config
  end

  defp update!(change) do
    {:ok, config} = read()
    updated = change.(config)
    write!(updated)
    updated
  end
end

defmodule BnestApp.Test.InMemory.StoragePorts.Lock do
  @moduledoc false

  @behaviour BnestApp.Storage.Ports.Lock

  alias BnestApp.Test.InMemory.StoragePorts

  @impl true
  def with_shared(fun) do
    StoragePorts.record(:shared_lock)
    fun.()
  end

  @impl true
  def with_exclusive(fun) do
    StoragePorts.record(:exclusive_lock)
    fun.()
  end
end

defmodule BnestApp.Test.InMemory.StoragePorts.DatabaseLifecycle do
  @moduledoc false

  @behaviour BnestApp.Storage.Ports.DatabaseLifecycle

  alias BnestApp.Test.InMemory.RecordBackend
  alias BnestApp.Test.InMemory.StoragePorts

  @impl true
  def ensure_started! do
    StoragePorts.record(:ensure_started)
    :ok
  end

  @impl true
  def ensure_started!(database_path) do
    StoragePorts.record({:ensure_started, database_path})
    :ok
  end

  @impl true
  def stop do
    StoragePorts.record(:stop)
    :ok
  end

  @impl true
  def migrate_schema! do
    StoragePorts.record(:migrate_schema)
    :ok
  end

  @impl true
  def record_backend do
    store =
      case StoragePorts.get(:sqlite_store, nil) do
        nil -> tap(RecordBackend.start(), &StoragePorts.put(:sqlite_store, &1))
        store -> store
      end

    {RecordBackend, store}
  end
end

defmodule BnestApp.Test.InMemory.StoragePorts.Maintenance do
  @moduledoc false

  @behaviour BnestApp.Storage.Ports.Maintenance

  alias BnestApp.Test.InMemory.RecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.StoragePorts.{ConfigStore, DatabaseLifecycle}

  @clean_run %{
    migration_id: "flat-files-v1-to-sqlite-v1",
    accepted: 1,
    blocked: 0,
    unsupported: 0,
    state: "copying"
  }

  @impl true
  def run_migration(flat_root), do: answer({:run_migration, flat_root}, :run, @clean_run)

  @impl true
  def migration_blocked?, do: answer(:migration_blocked?, :blocked?, false)

  @impl true
  def migration_started?, do: answer(:migration_started?, :started?, false)

  @impl true
  def parity_ok?(flat_root), do: answer({:parity_ok?, flat_root}, :parity?, true)

  @impl true
  def integrity_ok?, do: answer(:integrity_ok?, :integrity?, true)

  @impl true
  def restore_rehearsal_ok?, do: answer(:restore_rehearsal_ok?, :restore?, true)

  # Like the production adapter, activation switches the pointer to SQLite.
  @impl true
  def activate_sqlite! do
    ConfigStore.activate_sqlite_primary!()
    answer(:activate_sqlite!, :activate, :ok)
  end

  @impl true
  def relocate(directory), do: answer({:relocate, directory}, :relocate, {:ok, %{}})

  @impl true
  def retire(flat_root, generation, true),
    do: answer({:retire, flat_root, generation, true}, :retire, {:ok, 0})

  # Like the production adapter, a committed retirement needs SQLite to be primary at the
  # given generation and every flat record to have an identical SQLite copy; it then removes
  # the flat records from the flat store `put(:flat_store, store)` registered.
  def retire(flat_root, generation, false) do
    StoragePorts.record({:retire, flat_root, generation, false})
    flat = StoragePorts.get(:flat_store, nil)

    cond do
      ConfigStore.phase() != :sqlite_primary ->
        {:error, :not_sqlite_primary}

      ConfigStore.database_generation() != generation ->
        {:error, :generation_mismatch}

      is_nil(flat) or not Enum.all?(stored_records(flat), &copied_to_sqlite?/1) ->
        {:error, :unverified_flat_source}

      true ->
        Enum.each(stored_records(flat), fn {{type, identity}, record} ->
          :ok = RecordBackend.remove_exact(flat, type, identity, record)
        end)

        {:ok, ConfigStore.mark_legacy_retired!()}
    end
  end

  @impl true
  def purge_test_data(generation, dry_run?),
    do: answer({:purge_test_data, generation, dry_run?}, :purge, {:ok, %{}})

  @impl true
  def audit_schema(root), do: answer({:audit_schema, root}, :audit, {:ok, []})

  defp answer(call, key, default) do
    StoragePorts.record(call)
    StoragePorts.get(key, default)
  end

  defp stored_records(store),
    do: for({{_type, _identity}, _record} = entry <- RecordBackend.snapshot(store), do: entry)

  defp copied_to_sqlite?({{type, identity}, record}) do
    {_backend, sqlite} = DatabaseLifecycle.record_backend()
    RecordBackend.read(sqlite, type, identity) == {:ok, record}
  end
end
