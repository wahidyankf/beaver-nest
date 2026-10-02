defmodule BnestApp.Storage.Migration do
  @moduledoc """
  The one-time flat-file to SQLite migration. It inventories the flat sources through the
  `FlatSource` port, judges each under `BnestApp.Storage.Domain.FlatMigration`, copies the
  accepted ones and records every outcome through the `MigrationLedger` port, and checks
  parity before the authority switch. A retry reuses the items an interrupted or blocked
  pass already accepted. The Storage facade runs it under the storage lease.
  """

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.FlatMigration

  @type result :: %{
          migration_id: String.t(),
          accepted: non_neg_integer(),
          blocked: non_neg_integer(),
          unsupported: non_neg_integer(),
          state: String.t()
        }

  @doc "The supported flat sources under `flat_root`, in migration order."
  @spec inventory(String.t()) :: [String.t()]
  def inventory(flat_root), do: flat_root |> source().list() |> FlatMigration.inventory()

  @doc "Carries every inventoried source into SQLite once and records its outcome."
  @spec run(String.t()) :: result()
  def run(flat_root) do
    source = source()
    ledger = ledger()
    migration_id = FlatMigration.migration_id()
    relative_paths = inventory(flat_root)

    fingerprint =
      relative_paths
      |> Enum.map(&{&1, source.read!(flat_root, &1)})
      |> FlatMigration.source_fingerprint()

    ensure_run!(ledger, migration_id, fingerprint)
    kinds = Storage.record_kinds()

    outcomes =
      Enum.map(relative_paths, fn relative_path ->
        bytes = source.read!(flat_root, relative_path)
        process_item(ledger, migration_id, relative_path, bytes, kinds)
      end)

    %{accepted: accepted, blocked: blocked, unsupported: unsupported} =
      FlatMigration.outcome_counts(outcomes)

    state = FlatMigration.run_state(blocked, Storage.phase())
    :ok = ledger.update_run!(migration_id, state, fingerprint)

    %{
      migration_id: migration_id,
      accepted: accepted,
      blocked: blocked,
      unsupported: unsupported,
      state: state
    }
  end

  @doc "Whether any recorded item blocks the authority switch."
  @spec blocked?() :: boolean()
  def blocked?, do: ledger().blocked?()

  @doc "Whether every inventoried source still matches its migrated copy."
  @spec parity_ok?(String.t()) :: boolean()
  def parity_ok?(flat_root) do
    source = source()
    ledger = ledger()
    kinds = Storage.record_kinds()

    flat_root
    |> inventory()
    |> Enum.all?(fn relative_path ->
      source_matches?(ledger, relative_path, source.read!(flat_root, relative_path), kinds)
    end)
  end

  @doc "Makes SQLite the authoritative store and marks the run verified."
  @spec activate!() :: :ok
  def activate! do
    Storage.adapter(:config_store).activate_sqlite_primary!()
    :ok = ledger().mark_verified!(FlatMigration.migration_id(), timestamp())
  end

  defp ensure_run!(ledger, migration_id, fingerprint) do
    if ledger.run_started?(migration_id) do
      :ok
    else
      schema_sources = Storage.adapter(:database_lifecycle).schema_sources()

      ledger.start_run!(%{
        migration_id: migration_id,
        source_fingerprint: fingerprint,
        ddl_checksum: FlatMigration.ddl_checksum(schema_sources),
        state: "inventoried",
        started_at: timestamp()
      })
    end
  end

  defp process_item(ledger, migration_id, relative_path, bytes, kinds) do
    {:ok, classified} = FlatMigration.classify_source(relative_path)
    source_sha256 = FlatMigration.sha256(bytes)

    case FlatMigration.resume_decision(ledger.item(migration_id, relative_path), source_sha256) do
      :reuse ->
        :accepted

      :changed ->
        put_item!(ledger, relative_path, classified, {source_sha256, nil}, "changed_source")
        :changed

      :assess ->
        accept_or_reject(ledger, relative_path, classified, bytes, kinds)
    end
  end

  defp accept_or_reject(ledger, relative_path, {:record, _classification}, bytes, kinds) do
    case FlatMigration.assess_record(relative_path, bytes, kinds) do
      {:accepted, evidence} ->
        :ok =
          ledger.put_record!(
            evidence.classification,
            evidence.record,
            evidence.target_sha256,
            timestamp()
          )

        put_item!(
          ledger,
          relative_path,
          {:record, evidence.classification},
          {evidence.source_sha256, evidence.target_sha256},
          nil
        )

        :accepted

      {:invalid, evidence} ->
        put_item!(
          ledger,
          relative_path,
          {:record, evidence.classification},
          {evidence.source_sha256, nil},
          "malformed"
        )

        :invalid
    end
  end

  defp accept_or_reject(ledger, relative_path, {:recovery, recovery} = classified, bytes, _kinds) do
    source_sha256 = FlatMigration.sha256(bytes)

    :ok =
      ledger.put_recovery_source!(%{
        owner_kind: recovery.owner_kind,
        owner_key: recovery.owner_key,
        import_id: recovery.import_id,
        payload_blob: bytes,
        payload_sha256: source_sha256,
        byte_size: byte_size(bytes),
        inserted_at: timestamp()
      })

    if recovery_matches?(ledger, recovery, bytes) do
      put_item!(ledger, relative_path, classified, {source_sha256, source_sha256}, nil)
      :accepted
    else
      put_item!(ledger, relative_path, classified, {source_sha256, nil}, "recovery_collision")
      :invalid
    end
  end

  # An item with an error category is blocked: a malformed or colliding source is invalid,
  # and an accepted source that changed afterwards is changed.
  defp put_item!(ledger, relative_path, classified, {source_sha256, target_sha256}, category) do
    classification = FlatMigration.item_classification(classified)

    :ok =
      ledger.put_item!(%{
        migration_id: FlatMigration.migration_id(),
        source_relative_path: relative_path,
        record_type: classification.record_type,
        record_key: classification.record_key,
        source_sha256: source_sha256,
        target_sha256: target_sha256,
        outcome: item_outcome(category),
        error_category: category
      })
  end

  defp item_outcome(nil), do: "accepted"
  defp item_outcome("changed_source"), do: "changed"
  defp item_outcome(_category), do: "invalid"

  defp source_matches?(ledger, relative_path, bytes, kinds) do
    case FlatMigration.classify_source(relative_path) do
      {:ok, {:record, classification}} ->
        target =
          ledger.read_record(classification.type, FlatMigration.identity_of(classification))

        FlatMigration.record_matches?(bytes, target, Storage.phase(), kinds)

      {:ok, {:recovery, recovery}} ->
        recovery_matches?(ledger, recovery, bytes)
    end
  end

  defp recovery_matches?(ledger, recovery, bytes) do
    recovery.owner_kind
    |> ledger.recovery_source(recovery.owner_key, recovery.import_id)
    |> FlatMigration.recovery_matches?(bytes)
  end

  defp source, do: Storage.adapter(:flat_source)
  defp ledger, do: Storage.adapter(:migration_ledger)
  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
