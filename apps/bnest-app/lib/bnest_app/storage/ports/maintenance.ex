defmodule BnestApp.Storage.Ports.Maintenance do
  @moduledoc """
  The storage maintenance procedures on the database and the host: whether the flat-file
  migration started, the integrity and isolated-restore checks of its verification,
  relocation, retirement of verified legacy storage, removal of legacy test data, and the
  record-structure audit. The Storage facade sequences them; adapters perform them.
  """

  @callback migration_started?() :: boolean()
  @callback integrity_ok?() :: boolean()
  @callback restore_rehearsal_ok?() :: boolean()
  @callback relocate(directory :: String.t()) :: {:ok, map()} | {:error, atom()}
  @callback retire(flat_root :: String.t(), generation :: String.t(), dry_run? :: boolean()) ::
              {:ok, non_neg_integer() | map()} | {:error, atom()}
  @callback purge_test_data(generation :: String.t(), dry_run? :: boolean()) ::
              {:ok, map()} | {:error, atom()}
  @callback audit_schema(root :: String.t()) :: {:ok, [map()]} | {:error, atom()}
end
