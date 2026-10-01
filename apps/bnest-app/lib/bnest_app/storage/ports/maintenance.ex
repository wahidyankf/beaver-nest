defmodule BnestApp.Storage.Ports.Maintenance do
  @moduledoc """
  The storage maintenance procedures: the flat-file to SQLite migration and its verification,
  relocation, retirement of verified legacy storage, removal of legacy test data, and the
  record-structure audit. The Storage facade sequences them; adapters perform them.
  """

  @type migration_result :: %{
          migration_id: String.t(),
          accepted: non_neg_integer(),
          blocked: non_neg_integer(),
          unsupported: non_neg_integer(),
          state: String.t()
        }

  @callback run_migration(flat_root :: String.t()) :: migration_result()
  @callback migration_blocked?() :: boolean()
  @callback migration_started?() :: boolean()
  @callback parity_ok?(flat_root :: String.t()) :: boolean()
  @callback integrity_ok?() :: boolean()
  @callback restore_rehearsal_ok?() :: boolean()
  @callback activate_sqlite!() :: :ok
  @callback relocate(directory :: String.t()) :: {:ok, map()} | {:error, atom()}
  @callback retire(flat_root :: String.t(), generation :: String.t(), dry_run? :: boolean()) ::
              {:ok, non_neg_integer() | map()} | {:error, atom()}
  @callback purge_test_data(generation :: String.t(), dry_run? :: boolean()) ::
              {:ok, map()} | {:error, atom()}
  @callback audit_schema(root :: String.t()) :: {:ok, [map()]} | {:error, atom()}
end
