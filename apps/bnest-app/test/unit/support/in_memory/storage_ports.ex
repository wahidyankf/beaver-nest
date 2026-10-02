defmodule BnestApp.Test.InMemory.StoragePorts do
  @moduledoc """
  In-memory doubles for the Storage ports other than the record backend. They share one
  agent, started by `install/1` and linked to the test, which holds their state and the
  calls they receive in order. The configuration they replace is application-wide, so
  only one non-async test may install them at a time.
  """

  alias BnestApp.Test.InMemory.StoragePorts.{
    ConfigStore,
    DatabaseLifecycle,
    FlatSource,
    Lock,
    Maintenance,
    MigrationLedger
  }

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
        maintenance: Maintenance,
        flat_source: FlatSource,
        migration_ledger: MigrationLedger
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

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.Location
  alias BnestApp.Test.InMemory.StoragePorts

  # Named where the production adapter keeps it without an override; nothing is written there.
  @impl true
  def pointer_path, do: Location.config_directory() <> "/storage.json"

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
          "databaseDirectory" => Storage.default_directory(),
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

  # Like the production adapter, relocation keeps the previous directory as the legacy one.
  @impl true
  def relocate!(directory, generation) do
    {:ok, validated} = validate_directory(directory)

    update!(
      &Map.merge(&1, %{
        "legacyDatabaseDirectory" => &1["databaseDirectory"],
        "databaseDirectory" => validated,
        "databaseGeneration" => generation
      })
    )
  end

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

  # Synthetic committed schema sources; a test may replace them under :schema_sources.
  @impl true
  def schema_sources,
    do:
      StoragePorts.get(:schema_sources, [
        "CREATE TABLE bnest_records (record_type TEXT NOT NULL, record_key TEXT NOT NULL);",
        "CREATE INDEX bnest_records_owner_type ON bnest_records (owner_id, record_type);"
      ])

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

  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Test.InMemory.RecordBackend
  alias BnestApp.Test.InMemory.StoragePorts

  alias BnestApp.Test.InMemory.StoragePorts.{
    ConfigStore,
    DatabaseLifecycle,
    FlatSource,
    MigrationLedger
  }

  @placeholder ".gitkeep"

  @impl true
  def migration_started?, do: answer(:migration_started?, :started?, false)

  @impl true
  def integrity_ok?, do: answer(:integrity_ok?, :integrity?, true)

  @impl true
  def restore_rehearsal_ok?, do: answer(:restore_rehearsal_ok?, :restore?, true)

  # Like the production adapter, relocation needs SQLite to be primary and a valid destination;
  # it then moves the pointer to a new generation in one write, keeping the legacy directory.
  # The in-memory database itself has no location to copy.
  @impl true
  def relocate(directory) do
    StoragePorts.record({:relocate, directory})

    with {:ok, config} <- ConfigStore.read(),
         :sqlite_primary <- ConfigStore.phase(),
         {:ok, validated} <- ConfigStore.validate_directory(directory) do
      if validated == config["databaseDirectory"],
        do: {:ok, config},
        else: {:ok, ConfigStore.relocate!(validated, generation())}
    else
      :flat_primary -> {:error, :not_sqlite_primary}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def retire(flat_root, generation, true),
    do: answer({:retire, flat_root, generation, true}, :retire, {:ok, 0})

  # Like the production adapter, a committed retirement needs SQLite to be primary at the
  # given generation with a verified migration run, and every flat file but a placeholder to
  # match the checksum its accepted migration item recorded. It then removes those files,
  # keeping placeholders, and the legacy database with its sidecars, which are reported as
  # `{:remove_legacy_database, path}` calls. A flat record store `put(:flat_store, store)`
  # registered stands for the same files: each record needs an identical SQLite copy and is
  # removed with them.
  def retire(flat_root, generation, false) do
    StoragePorts.record({:retire, flat_root, generation, false})
    flat = StoragePorts.get(:flat_store, nil)
    {placeholders, files} = Enum.split_with(FlatSource.files(flat_root), &placeholder?/1)

    cond do
      ConfigStore.phase() != :sqlite_primary ->
        {:error, :not_sqlite_primary}

      ConfigStore.database_generation() != generation ->
        {:error, :generation_mismatch}

      not migration_verified?() ->
        {:error, :database_not_verified}

      not Enum.all?(files, &verified_file?/1) ->
        {:error, :unverified_flat_source}

      not is_nil(flat) and not Enum.all?(stored_records(flat), &copied_to_sqlite?/1) ->
        {:error, :unverified_flat_source}

      true ->
        FlatSource.put_files(flat_root, placeholders)
        remove_flat_records(flat)
        {:ok, config} = ConfigStore.read()
        remove_legacy_database(config)
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

  # Each relocation records a call first, so the call count names a fresh generation.
  defp generation, do: "generation-" <> Integer.to_string(length(StoragePorts.calls()))

  defp placeholder?({relative_path, _bytes}),
    do: relative_path |> String.split("/") |> List.last() == @placeholder

  defp migration_verified? do
    migration_id = FlatMigration.migration_id()

    Enum.any?(
      MigrationLedger.state().runs,
      &match?(%{migration_id: ^migration_id, state: "verified"}, &1)
    )
  end

  defp verified_file?({relative_path, bytes}) do
    case MigrationLedger.item(FlatMigration.migration_id(), relative_path) do
      %{outcome: "accepted", source_sha256: checksum} -> FlatMigration.sha256(bytes) == checksum
      _missing -> false
    end
  end

  defp remove_flat_records(nil), do: :ok

  defp remove_flat_records(flat),
    do:
      Enum.each(stored_records(flat), fn {{type, identity}, record} ->
        :ok = RecordBackend.remove_exact(flat, type, identity, record)
      end)

  defp remove_legacy_database(%{"legacyDatabaseDirectory" => directory} = config) do
    database = directory <> "/" <> config["databaseFilename"]

    Enum.each(
      [database, database <> "-wal", database <> "-shm"],
      &StoragePorts.record({:remove_legacy_database, &1})
    )
  end

  defp remove_legacy_database(_config), do: :ok

  defp stored_records(store),
    do: for({{_type, _identity}, _record} = entry <- RecordBackend.snapshot(store), do: entry)

  defp copied_to_sqlite?({{type, identity}, record}) do
    {_backend, sqlite} = DatabaseLifecycle.record_backend()
    RecordBackend.read(sqlite, type, identity) == {:ok, record}
  end
end

defmodule BnestApp.Test.InMemory.StoragePorts.FlatSource do
  @moduledoc """
  The legacy flat-file tree as lists of `{relative_path, bytes}` per root, listed in the
  order a test put them, so only the migration's own ordering yields path order.
  """

  @behaviour BnestApp.Storage.Ports.FlatSource

  alias BnestApp.Test.InMemory.StoragePorts

  def put_files(flat_root, files), do: StoragePorts.put({:flat_files, flat_root}, files)

  def files(flat_root), do: StoragePorts.get({:flat_files, flat_root}, [])

  @impl true
  def list(flat_root), do: Enum.map(files(flat_root), &elem(&1, 0))

  @impl true
  def read!(flat_root, relative_path) do
    case List.keyfind(files(flat_root), relative_path, 0) do
      {^relative_path, bytes} -> bytes
      nil -> raise KeyError, key: relative_path, term: flat_root
    end
  end
end

defmodule BnestApp.Test.InMemory.StoragePorts.MigrationLedger do
  @moduledoc """
  The migration ledger in the shared agent. Runs are a list, so a duplicate run start stays
  visible, and every write is logged in order, so a retry that rewrites an accepted item
  can be seen. Migrated records go to the SQLite record store `DatabaseLifecycle` names, so
  repository reads through `Records` see them.
  """

  @behaviour BnestApp.Storage.Ports.MigrationLedger

  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Test.InMemory.RecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.StoragePorts.DatabaseLifecycle

  @empty %{runs: [], items: %{}, recovery: %{}, writes: []}

  @doc "The ledger, with its writes oldest first."
  def state, do: Map.update!(ledger(), :writes, &Enum.reverse/1)

  @doc """
  Lets `count` more record writes through, then fails every later one as an interrupted
  process would, until `resume/0`.
  """
  def interrupt_after(count), do: StoragePorts.put(:record_write_budget, count)

  def resume, do: StoragePorts.put(:record_write_budget, :unlimited)

  @impl true
  def run_started?(migration_id),
    do: Enum.any?(ledger().runs, &(&1.migration_id == migration_id))

  @impl true
  def start_run!(run) do
    update({:start_run, run.migration_id}, fn ledger ->
      %{ledger | runs: ledger.runs ++ [Map.put(run, :verified_at, nil)]}
    end)
  end

  @impl true
  def update_run!(migration_id, state, fingerprint),
    do:
      update_runs({:update_run, migration_id, state}, migration_id, %{
        state: state,
        source_fingerprint: fingerprint
      })

  @impl true
  def mark_verified!(migration_id, verified_at),
    do:
      update_runs({:mark_verified, migration_id}, migration_id, %{
        state: "verified",
        verified_at: verified_at
      })

  @impl true
  def item(migration_id, relative_path) do
    case Map.get(ledger().items, {migration_id, relative_path}) do
      nil -> nil
      item -> Map.take(item, [:outcome, :source_sha256])
    end
  end

  @impl true
  def put_item!(item) do
    update({:put_item, item.source_relative_path, item.outcome}, fn ledger ->
      %{
        ledger
        | items: Map.put(ledger.items, {item.migration_id, item.source_relative_path}, item)
      }
    end)
  end

  @impl true
  def blocked?,
    do: Enum.any?(Map.values(ledger().items), &(&1.outcome in ["invalid", "changed", "failed"]))

  @impl true
  def put_record!(classification, record, _target_sha256, _now) do
    spend_record_write!()
    store = sqlite_store()
    identity = FlatMigration.identity_of(classification)

    case RecordBackend.replace(store, classification.type, identity, record) do
      {:ok, _replaced} ->
        :ok

      {:error, :missing} ->
        {:ok, _new} = RecordBackend.put_new(store, classification.type, identity, record)
    end

    update({:put_record, classification.type, identity}, & &1)
  end

  @impl true
  def read_record(type, identity), do: RecordBackend.read(sqlite_store(), type, identity)

  @impl true
  def put_recovery_source!(row) do
    key = {row.owner_kind, row.owner_key, row.import_id}

    update({:put_recovery_source, key}, fn ledger ->
      %{ledger | recovery: Map.put_new(ledger.recovery, key, row)}
    end)
  end

  @impl true
  def recovery_source(owner_kind, owner_key, import_id) do
    case Map.get(ledger().recovery, {owner_kind, owner_key, import_id}) do
      nil ->
        nil

      row ->
        %{payload: row.payload_blob, payload_sha256: row.payload_sha256, byte_size: row.byte_size}
    end
  end

  defp ledger, do: StoragePorts.get(:migration_ledger, @empty)

  defp spend_record_write! do
    case StoragePorts.get(:record_write_budget, :unlimited) do
      :unlimited -> :ok
      0 -> raise "the migration was interrupted before this record write"
      count -> StoragePorts.put(:record_write_budget, count - 1)
    end
  end

  defp update(write, change) do
    ledger = change.(ledger())
    StoragePorts.put(:migration_ledger, %{ledger | writes: [write | ledger.writes]})
    :ok
  end

  defp update_runs(write, migration_id, changes) do
    update(write, fn ledger ->
      runs =
        Enum.map(ledger.runs, fn
          %{migration_id: ^migration_id} = run -> Map.merge(run, changes)
          run -> run
        end)

      %{ledger | runs: runs}
    end)
  end

  defp sqlite_store do
    {_backend, store} = DatabaseLifecycle.record_backend()
    store
  end
end
