defmodule BnestApp.Storage.Ports.MigrationLedger do
  @moduledoc """
  The target database of the one-time flat-file migration: its run and item ledger, the
  migrated records, and the preserved legacy recovery payloads.
  """

  @type item :: %{
          migration_id: String.t(),
          source_relative_path: String.t(),
          record_type: String.t(),
          record_key: String.t(),
          source_sha256: String.t(),
          target_sha256: String.t() | nil,
          outcome: String.t(),
          error_category: String.t() | nil
        }

  @type recovery_source :: %{
          owner_kind: String.t(),
          owner_key: String.t(),
          import_id: String.t(),
          payload_blob: binary(),
          payload_sha256: String.t(),
          byte_size: non_neg_integer(),
          inserted_at: String.t()
        }

  @callback run_started?(migration_id :: String.t()) :: boolean()

  @doc "Records a new run with its source fingerprint and schema checksum."
  @callback start_run!(run :: map()) :: :ok

  @callback update_run!(
              migration_id :: String.t(),
              state :: String.t(),
              fingerprint :: String.t()
            ) ::
              :ok

  @callback mark_verified!(migration_id :: String.t(), verified_at :: String.t()) :: :ok

  @doc "The outcome and source checksum an earlier pass recorded for a source, if any."
  @callback item(migration_id :: String.t(), relative_path :: String.t()) ::
              %{outcome: String.t(), source_sha256: String.t()} | nil

  @doc "Inserts or replaces the item for its migration and source path."
  @callback put_item!(item()) :: :ok

  @doc "Whether any recorded item is invalid, changed or failed."
  @callback blocked?() :: boolean()

  @doc "Inserts or replaces a migrated record under its classified identity."
  @callback put_record!(
              classification :: map(),
              record :: map(),
              target_sha256 :: String.t(),
              now :: String.t()
            ) :: :ok

  @callback read_record(type :: atom(), identity :: term()) :: {:ok, map()} | {:error, atom()}

  @doc "Stores a recovery payload unless one already exists for its owner and import."
  @callback put_recovery_source!(recovery_source()) :: :ok

  @callback recovery_source(
              owner_kind :: String.t(),
              owner_key :: String.t(),
              import_id :: String.t()
            ) ::
              %{payload: binary(), payload_sha256: String.t(), byte_size: non_neg_integer()}
              | nil
end
