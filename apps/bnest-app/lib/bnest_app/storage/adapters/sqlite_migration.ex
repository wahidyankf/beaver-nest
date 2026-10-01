defmodule BnestApp.Storage.Adapters.SqliteMigration do
  @moduledoc """
  Carries the flat-file records into SQLite under the `BnestApp.Storage.Domain.FlatMigration`
  rules, records each item's outcome, and verifies parity, integrity and a restore.
  """

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteRecordBackend
  alias BnestApp.Storage.Domain.FlatMigration

  import Ecto.Query

  @spec inventory(String.t()) :: [String.t()]
  def inventory(flat_root) do
    flat_root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, flat_root))
    |> Enum.filter(&match?({:ok, _classification}, FlatMigration.classify_source(&1)))
    |> FlatMigration.order_inventory()
  end

  @spec source_fingerprint([String.t()], String.t()) :: String.t()
  def source_fingerprint(relative_paths, flat_root) do
    relative_paths
    |> Enum.map_join("\n", &(&1 <> ":" <> source_sha256(flat_root, &1)))
    |> FlatMigration.sha256()
  end

  @spec run(String.t(), module()) :: %{
          migration_id: String.t(),
          accepted: non_neg_integer(),
          blocked: non_neg_integer(),
          unsupported: non_neg_integer(),
          state: String.t()
        }
  def run(flat_root, repo \\ SqliteRepo) do
    relative_paths = inventory(flat_root)
    fingerprint = source_fingerprint(relative_paths, flat_root)
    now = timestamp()
    ensure_run!(repo, fingerprint, now)

    kinds = Storage.record_kinds()
    outcomes = Enum.map(relative_paths, &process_item(repo, flat_root, &1, kinds))

    %{accepted: accepted, blocked: blocked, unsupported: unsupported} =
      FlatMigration.outcome_counts(outcomes)

    state = FlatMigration.run_state(blocked, FileConfigStore.phase())
    update_run_state!(repo, fingerprint, state)

    %{
      migration_id: FlatMigration.migration_id(),
      accepted: accepted,
      blocked: blocked,
      unsupported: unsupported,
      state: state
    }
  end

  @spec blocked?(module()) :: boolean()
  def blocked?(repo \\ SqliteRepo) do
    from(i in "bnest_migration_items", where: i.outcome in ["invalid", "changed", "failed"])
    |> repo.exists?()
  end

  @spec started?(module()) :: boolean()
  def started?(repo \\ SqliteRepo) do
    migration_id = FlatMigration.migration_id()

    from(r in "bnest_migration_runs", where: r.migration_id == ^migration_id)
    |> repo.exists?()
  end

  @spec parity_ok?(String.t(), module()) :: boolean()
  def parity_ok?(flat_root, repo \\ SqliteRepo) do
    store = SqliteRecordBackend.new(repo)
    kinds = Storage.record_kinds()

    inventory(flat_root)
    |> Enum.all?(&source_matches?(repo, store, flat_root, &1, kinds))
  end

  @spec integrity_ok?(module()) :: boolean()
  def integrity_ok?(repo \\ SqliteRepo) do
    case repo.query("PRAGMA quick_check") do
      {:ok, %{rows: [["ok"]]}} -> true
      _other -> false
    end
  end

  @spec restore_rehearsal(String.t(), module()) :: boolean()
  def restore_rehearsal(destination_path, repo \\ SqliteRepo) do
    File.rm(destination_path)
    {:ok, _result} = repo.query("VACUUM INTO ?", [destination_path])
    ok = File.exists?(destination_path)
    File.rm(destination_path)
    ok
  end

  @spec activate!(module()) :: :ok
  def activate!(repo \\ SqliteRepo) do
    FileConfigStore.activate_sqlite_primary!()
    migration_id = FlatMigration.migration_id()

    from(r in "bnest_migration_runs", where: r.migration_id == ^migration_id)
    |> repo.update_all(set: [state: "verified", verified_at: timestamp()])

    :ok
  end

  defp process_item(repo, flat_root, relative_path, kinds) do
    {:ok, source} = FlatMigration.classify_source(relative_path)
    source_bytes = File.read!(Path.join(flat_root, relative_path))
    source_sha256 = FlatMigration.sha256(source_bytes)

    existing = fetch_item(repo, relative_path)

    cond do
      existing && existing.outcome == "accepted" && existing.source_sha256 == source_sha256 ->
        :accepted

      existing && existing.outcome == "accepted" && existing.source_sha256 != source_sha256 ->
        upsert_item!(
          repo,
          relative_path,
          FlatMigration.item_classification(source),
          source_sha256,
          nil,
          "changed",
          "changed_source"
        )

        :changed

      true ->
        accept_or_reject(repo, relative_path, source, source_bytes, source_sha256, kinds)
    end
  end

  defp accept_or_reject(
         repo,
         relative_path,
         {:record, _classification},
         source_bytes,
         _source_sha256,
         kinds
       ) do
    case FlatMigration.assess_record(relative_path, source_bytes, kinds) do
      {:accepted, evidence} ->
        write_record!(
          repo,
          evidence.classification,
          evidence.record,
          evidence.target_sha256
        )

        upsert_item!(
          repo,
          relative_path,
          evidence.classification,
          evidence.source_sha256,
          evidence.target_sha256,
          "accepted",
          nil
        )

        :accepted

      {:invalid, evidence} ->
        upsert_item!(
          repo,
          relative_path,
          evidence.classification,
          evidence.source_sha256,
          nil,
          "invalid",
          "malformed"
        )

        :invalid

      {:unsupported, _evidence} ->
        raise "recognized migration record became unsupported"
    end
  end

  defp accept_or_reject(
         repo,
         relative_path,
         {:recovery, classification} = source,
         source_bytes,
         source_sha256,
         _kinds
       ) do
    now = timestamp()

    repo.insert_all(
      "bnest_recovery_sources",
      [
        %{
          owner_kind: classification.owner_kind,
          owner_key: classification.owner_key,
          import_id: classification.import_id,
          payload_blob: source_bytes,
          payload_sha256: source_sha256,
          byte_size: byte_size(source_bytes),
          inserted_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:owner_kind, :owner_key, :import_id]
    )

    if recovery_matches?(repo, classification, source_bytes) do
      upsert_item!(
        repo,
        relative_path,
        FlatMigration.item_classification(source),
        source_sha256,
        source_sha256,
        "accepted",
        nil
      )

      :accepted
    else
      upsert_item!(
        repo,
        relative_path,
        FlatMigration.item_classification(source),
        source_sha256,
        nil,
        "invalid",
        "recovery_collision"
      )

      :invalid
    end
  end

  defp write_record!(repo, classification, record, target_sha256) do
    now = timestamp()

    repo.insert_all(
      "bnest_records",
      [
        %{
          record_type: classification.record_type,
          record_key: classification.record_key,
          owner_id: classification.owner_id,
          schema_version: record["schemaVersion"],
          revision: record["revision"],
          payload_json: Jason.encode!(record),
          payload_sha256: target_sha256,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict:
        {:replace,
         [:owner_id, :schema_version, :revision, :payload_json, :payload_sha256, :updated_at]},
      conflict_target: [:record_type, :record_key]
    )
  end

  defp upsert_item!(
         repo,
         relative_path,
         classification,
         source_sha256,
         target_sha256,
         outcome,
         error_category
       ) do
    repo.insert_all(
      "bnest_migration_items",
      [
        %{
          migration_id: FlatMigration.migration_id(),
          source_relative_path: relative_path,
          record_type: classification.record_type,
          record_key: classification.record_key,
          source_sha256: source_sha256,
          target_sha256: target_sha256,
          outcome: outcome,
          error_category: error_category
        }
      ],
      on_conflict: {:replace, [:source_sha256, :target_sha256, :outcome, :error_category]},
      conflict_target: [:migration_id, :source_relative_path]
    )
  end

  defp fetch_item(repo, relative_path) do
    migration_id = FlatMigration.migration_id()

    from(i in "bnest_migration_items",
      where: i.migration_id == ^migration_id and i.source_relative_path == ^relative_path,
      select: %{outcome: i.outcome, source_sha256: i.source_sha256}
    )
    |> repo.one()
  end

  defp ensure_run!(repo, fingerprint, now) do
    if started?(repo) do
      :ok
    else
      repo.insert_all("bnest_migration_runs", [
        %{
          migration_id: FlatMigration.migration_id(),
          source_fingerprint: fingerprint,
          ddl_checksum: ddl_checksum(),
          state: "inventoried",
          started_at: now
        }
      ])

      :ok
    end
  end

  defp update_run_state!(repo, fingerprint, state) do
    migration_id = FlatMigration.migration_id()

    from(r in "bnest_migration_runs", where: r.migration_id == ^migration_id)
    |> repo.update_all(set: [state: state, source_fingerprint: fingerprint])
  end

  defp source_matches?(repo, store, flat_root, relative_path, kinds) do
    source_bytes = File.read!(Path.join(flat_root, relative_path))

    case FlatMigration.classify_source(relative_path) do
      {:ok, {:record, classification}} ->
        target =
          SqliteRecordBackend.read(
            store,
            classification.type,
            FlatMigration.identity_of(classification)
          )

        FlatMigration.record_matches?(source_bytes, target, FileConfigStore.phase(), kinds)

      {:ok, {:recovery, classification}} ->
        recovery_matches?(repo, classification, source_bytes)
    end
  end

  defp recovery_matches?(repo, classification, source_bytes) do
    expected_sha256 = FlatMigration.sha256(source_bytes)

    case repo.query!(
           "SELECT payload_blob, payload_sha256, byte_size FROM bnest_recovery_sources WHERE owner_kind = ? AND owner_key = ? AND import_id = ?",
           [classification.owner_kind, classification.owner_key, classification.import_id]
         ).rows do
      [[^source_bytes, ^expected_sha256, byte_size]] -> byte_size == byte_size(source_bytes)
      _mismatch -> false
    end
  end

  defp source_sha256(flat_root, relative_path) do
    Path.join(flat_root, relative_path) |> File.read!() |> FlatMigration.sha256()
  end

  defp ddl_checksum do
    priv_dir = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

    priv_dir
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map_join(&File.read!/1)
    |> FlatMigration.sha256()
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
