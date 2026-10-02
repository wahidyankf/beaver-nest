defmodule BnestApp.Storage do
  @moduledoc """
  The Storage bounded context: where Bnest's records live, which backend owns them, and the
  procedures that move them between backends and locations.

  This module is the context's application-service facade. Its adapters come from
  application configuration under `config :bnest_app, BnestApp.Storage`, one per port in
  `BnestApp.Storage.Ports`, so a test can supply in-memory doubles.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [Jason],
    exports: [Records, {Domain, []}, {Ports, []}]

  alias BnestApp.Storage.Domain.Location
  alias BnestApp.Storage.Domain.RecordSchema
  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Migration
  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.Records

  @type migration_report :: %{
          run: Migration.result(),
          verification: %{parity: boolean(), integrity: boolean(), restore: boolean()} | nil
        }

  @doc "The configured adapter for a Storage port, such as `:lock` or `:config_store`."
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc "The record kinds that other contexts registered with Storage."
  @spec record_kinds() :: [module()]
  def record_kinds,
    do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.get(:record_kinds, [])

  @spec validate_record(term()) :: {:ok, map()} | {:error, atom()}
  def validate_record(record), do: RecordSchema.validate(record, record_kinds())

  @doc "The current UTC time as a record timestamp."
  @spec now() :: String.t()
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  # Database lifecycle

  @spec ensure_started!() :: :ok
  def ensure_started!, do: adapter(:database_lifecycle).ensure_started!()

  @spec ensure_started!(String.t()) :: :ok
  def ensure_started!(database_path),
    do: adapter(:database_lifecycle).ensure_started!(database_path)

  @spec stop() :: :ok
  def stop, do: adapter(:database_lifecycle).stop()

  @doc "The SQLite record backend, with its database started."
  @spec record_backend() :: {module(), RecordBackend.state()}
  def record_backend do
    lifecycle = adapter(:database_lifecycle)
    :ok = lifecycle.ensure_started!()
    lifecycle.record_backend()
  end

  # Storage pointer

  @spec database_path() :: String.t()
  def database_path, do: adapter(:config_store).resolved_database_path()

  @spec database_generation() :: String.t() | nil
  def database_generation, do: adapter(:config_store).database_generation()

  @spec phase() :: :flat_primary | :sqlite_primary
  def phase, do: adapter(:config_store).phase()

  @spec default_directory() :: String.t()
  def default_directory,
    do: Location.default_directory(Application.get_env(:bnest_app, :storage_profile, :production))

  @spec validate_directory(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_directory(directory), do: adapter(:config_store).validate_directory(directory)

  @doc """
  Records the chosen database directory. The pointer is immutable once written, so a second
  choice returns `{:error, :immutable}`.
  """
  @spec persist_directory(String.t()) :: {:ok, map()} | {:error, atom()}
  def persist_directory(directory) do
    store = adapter(:config_store)

    persist_directory(directory, %{
      read: &store.read/0,
      validate: &store.validate_directory/1,
      write: &store.write!/1
    })
  end

  @doc false
  @spec persist_directory(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def persist_directory(directory, %{read: read, validate: validate, write: write}) do
    with {:error, :absent} <- guard_immutable(read),
         {:ok, validated} <- validate.(directory) do
      config = %{
        "schemaVersion" => 1,
        "databaseDirectory" => validated,
        "databaseFilename" => Location.filename(),
        "phase" => "flat_primary",
        "migrationId" => "flat-files-v1-to-sqlite-v1"
      }

      write.(config)

      {:ok, config}
    else
      {:ok, _existing} -> {:error, :immutable}
      {:error, reason} -> {:error, reason}
    end
  end

  # Storage lease

  @spec with_shared_lock((-> result)) :: result when result: var
  def with_shared_lock(fun), do: adapter(:lock).with_shared(fun)

  @spec with_exclusive_lock((-> result)) :: result when result: var
  def with_exclusive_lock(fun), do: adapter(:lock).with_exclusive(fun)

  @doc """
  The record store that owns the records now: `Records` once SQLite is primary, otherwise the
  flat-file store itself.
  """
  @spec active_store() :: module() | RecordBackend.state()
  def active_store do
    case phase() do
      :sqlite_primary -> Records
      :flat_primary -> Records.store()
    end
  end

  # Browser import

  @spec import_browser(String.t(), map()) :: {:ok, map()} | {:error, atom(), map() | nil}
  def import_browser(owner_id, source), do: Import.browser(Records.store(), owner_id, source)

  @spec import_absent_theme(String.t()) :: {:ok, map()} | {:error, atom()}
  def import_absent_theme(owner_id), do: Import.absent_theme(Records.store(), owner_id)

  # Maintenance

  @doc """
  Runs the flat-file to SQLite migration under the exclusive storage lease, as the managed
  CLI flow does. With `activate?`, a clean run is verified and switches storage authority.
  """
  @spec migrate(String.t(), boolean()) ::
          {:ok, :dry_run | :activated, migration_report()}
          | {:error, :blocked | :verification_failed, migration_report()}
  def migrate(flat_root, activate?) do
    with_exclusive_lock(fn ->
      config = adapter(:config_store).ensure_default!()

      start_and_migrate_schema!(
        Path.join(config["databaseDirectory"], config["databaseFilename"])
      )

      maintenance = adapter(:maintenance)
      run = Migration.run(flat_root)

      cond do
        run.blocked > 0 or Migration.blocked?() ->
          {:error, :blocked, %{run: run, verification: nil}}

        not activate? ->
          {:ok, :dry_run, %{run: run, verification: nil}}

        true ->
          verify_and_activate(maintenance, flat_root, run)
      end
    end)
  end

  @doc """
  Moves the flat-file records into SQLite for the browser flow, and activates SQLite when the
  run is clean and verified. It returns the migration run.
  """
  @spec move_data(String.t()) :: Migration.result()
  def move_data(flat_root) do
    adapter(:config_store).ensure_default!()
    start_and_migrate_schema!(database_path())
    maintenance = adapter(:maintenance)
    run = Migration.run(flat_root)

    if run.blocked == 0 and maintenance.integrity_ok?() and Migration.parity_ok?(flat_root),
      do: Migration.activate!()

    run
  end

  @spec migration_started?() :: boolean()
  def migration_started?, do: adapter(:maintenance).migration_started?()

  @spec relocate(String.t()) :: {:ok, map()} | {:error, atom()}
  def relocate(directory), do: adapter(:maintenance).relocate(directory)

  @spec retire(String.t(), String.t(), boolean()) ::
          {:ok, non_neg_integer() | map()} | {:error, atom()}
  def retire(flat_root, generation, dry_run?),
    do: adapter(:maintenance).retire(flat_root, generation, dry_run?)

  @spec purge_test_data(String.t(), boolean()) :: {:ok, map()} | {:error, atom()}
  def purge_test_data(generation, dry_run?),
    do: adapter(:maintenance).purge_test_data(generation, dry_run?)

  @spec audit_schema(String.t()) :: {:ok, [map()]} | {:error, atom()}
  def audit_schema(root), do: adapter(:maintenance).audit_schema(root)

  defp start_and_migrate_schema!(database_path) do
    lifecycle = adapter(:database_lifecycle)
    :ok = lifecycle.ensure_started!(database_path)
    :ok = lifecycle.migrate_schema!()
  end

  defp verify_and_activate(maintenance, flat_root, run) do
    verification = %{
      parity: Migration.parity_ok?(flat_root),
      integrity: maintenance.integrity_ok?(),
      restore: maintenance.restore_rehearsal_ok?()
    }

    report = %{run: run, verification: verification}

    if verification.parity and verification.integrity and verification.restore do
      :ok = Migration.activate!()
      {:ok, :activated, report}
    else
      {:error, :verification_failed, report}
    end
  end

  defp guard_immutable(read) do
    case read.() do
      {:ok, _config} -> {:ok, :exists}
      {:error, :absent} -> {:error, :absent}
      {:error, :invalid} -> {:error, :invalid}
    end
  end
end
