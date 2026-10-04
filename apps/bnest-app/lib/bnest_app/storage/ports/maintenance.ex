defmodule BnestApp.Storage.Ports.Maintenance do
  @moduledoc """
  The storage maintenance procedures on the database and the host: whether the flat-file
  migration started, the integrity and isolated-restore checks of its verification,
  relocation, retirement of verified legacy storage, removal of legacy test data, the
  record-structure audit, and private scratch copies of the database for read-only tools. The
  Storage facade sequences them; adapters perform them.
  """

  @typedoc """
  A scratch copy of the database: where it is, and whatever else the adapter needs to close it.
  """
  @type database_copy :: %{required(:database_path) => String.t(), optional(atom()) => term()}

  @callback migration_started?() :: boolean()
  @callback integrity_ok?() :: boolean()
  @callback restore_rehearsal_ok?() :: boolean()
  @callback relocate(directory :: String.t()) :: {:ok, map()} | {:error, atom()}
  @callback retire(flat_root :: String.t(), generation :: String.t(), dry_run? :: boolean()) ::
              {:ok, non_neg_integer() | map()} | {:error, atom()}
  @callback purge_test_data(generation :: String.t(), dry_run? :: boolean()) ::
              {:ok, map()} | {:error, atom()}
  @callback audit_schema(root :: String.t()) :: {:ok, [map()]} | {:error, atom()}

  @doc """
  Copies the database at `source` and its write-ahead log into a fresh private directory of
  their own, each keeping its name, and points the storage pointer at the copy, so the
  database that storage resolves is the copy. It never opens `source`. A copy that cannot be
  made leaves nothing behind.
  """
  @callback open_database_copy(source :: String.t()) ::
              {:ok, database_copy()} | {:error, :copy_failed}

  @doc "Restores the storage pointer `open_database_copy/1` replaced and removes the copy."
  @callback close_database_copy(database_copy()) :: :ok
end
