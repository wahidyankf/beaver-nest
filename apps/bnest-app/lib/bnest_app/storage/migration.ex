defmodule BnestApp.Storage.Migration do
  @moduledoc false

  alias BnestApp.DataRepository.CanonicalJson
  alias BnestApp.DataRepository.Schema
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config
  alias BnestApp.Storage.RecordMap

  import Ecto.Query

  @migration_id "flat-files-v1-to-sqlite-v1"

  @spec migration_id() :: String.t()
  def migration_id, do: @migration_id

  @spec inventory(String.t()) :: [String.t()]
  def inventory(flat_root) do
    flat_root
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, flat_root))
    |> Enum.filter(&match?({:ok, _classification}, RecordMap.classify(&1)))
    |> Enum.sort()
  end

  @spec source_fingerprint([String.t()], String.t()) :: String.t()
  def source_fingerprint(relative_paths, flat_root) do
    relative_paths
    |> Enum.map_join("\n", &(&1 <> ":" <> source_sha256(flat_root, &1)))
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
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

    outcomes = Enum.map(relative_paths, &process_item(repo, flat_root, &1))

    accepted = Enum.count(outcomes, &(&1 == :accepted))
    blocked = Enum.count(outcomes, &(&1 in [:invalid, :changed]))

    state = if blocked > 0, do: "failed", else: "copying"
    update_run_state!(repo, fingerprint, state)

    %{
      migration_id: @migration_id,
      accepted: accepted,
      blocked: blocked,
      unsupported: 0,
      state: state
    }
  end

  @spec blocked?(module()) :: boolean()
  def blocked?(repo \\ SqliteRepo) do
    from(i in "bnest_migration_items", where: i.outcome in ["invalid", "changed", "failed"])
    |> repo.exists?()
  end

  @spec parity_ok?(String.t(), module()) :: boolean()
  def parity_ok?(flat_root, repo \\ SqliteRepo) do
    alias BnestApp.DataRepository.SqliteStore

    store = SqliteStore.new(repo)

    inventory(flat_root)
    |> Enum.all?(fn relative_path ->
      {:ok, classification} = RecordMap.classify(relative_path)
      source_bytes = File.read!(Path.join(flat_root, relative_path))

      with {:ok, source_record} <- Jason.decode(source_bytes),
           {:ok, ^source_record} <- Schema.validate(source_record),
           {:ok, target_record} <-
             SqliteStore.read(store, classification.type, identity_of(classification)) do
        target_record == source_record
      else
        _mismatch -> false
      end
    end)
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
    Config.activate_sqlite_primary!()

    from(r in "bnest_migration_runs", where: r.migration_id == ^@migration_id)
    |> repo.update_all(set: [state: "verified", verified_at: timestamp()])

    :ok
  end

  defp process_item(repo, flat_root, relative_path) do
    {:ok, classification} = RecordMap.classify(relative_path)
    source_bytes = File.read!(Path.join(flat_root, relative_path))
    source_sha256 = sha256(source_bytes)

    existing = fetch_item(repo, relative_path)

    cond do
      existing && existing.outcome == "accepted" && existing.source_sha256 == source_sha256 ->
        :accepted

      existing && existing.outcome == "accepted" && existing.source_sha256 != source_sha256 ->
        upsert_item!(
          repo,
          relative_path,
          classification,
          source_sha256,
          nil,
          "changed",
          "changed_source"
        )

        :changed

      true ->
        accept_or_reject(repo, relative_path, classification, source_bytes, source_sha256)
    end
  end

  defp accept_or_reject(repo, relative_path, classification, source_bytes, source_sha256) do
    with {:ok, record} <- Jason.decode(source_bytes),
         {:ok, ^record} <- Schema.validate(record) do
      target_sha256 = CanonicalJson.sha256(record)
      write_record!(repo, classification, record, target_sha256)

      upsert_item!(
        repo,
        relative_path,
        classification,
        source_sha256,
        target_sha256,
        "accepted",
        nil
      )

      :accepted
    else
      _invalid ->
        upsert_item!(
          repo,
          relative_path,
          classification,
          source_sha256,
          nil,
          "invalid",
          "malformed"
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
          migration_id: @migration_id,
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
    from(i in "bnest_migration_items",
      where: i.migration_id == ^@migration_id and i.source_relative_path == ^relative_path,
      select: %{outcome: i.outcome, source_sha256: i.source_sha256}
    )
    |> repo.one()
  end

  defp ensure_run!(repo, fingerprint, now) do
    from(r in "bnest_migration_runs", where: r.migration_id == ^@migration_id)
    |> repo.exists?()
    |> case do
      true ->
        :ok

      false ->
        repo.insert_all("bnest_migration_runs", [
          %{
            migration_id: @migration_id,
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
    from(r in "bnest_migration_runs", where: r.migration_id == ^@migration_id)
    |> repo.update_all(set: [state: state, source_fingerprint: fingerprint])
  end

  defp identity_of(%{type: :bootstrap}), do: nil
  defp identity_of(%{type: :schema_registry}), do: nil

  defp identity_of(%{type: :browser_import, owner_id: owner, record_key: key}) do
    [_owner, import_id] = String.split(key, ":", parts: 2)
    {owner, import_id}
  end

  defp identity_of(%{record_key: key}), do: key

  defp source_sha256(flat_root, relative_path) do
    Path.join(flat_root, relative_path) |> File.read!() |> sha256()
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp ddl_checksum do
    priv_dir = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

    priv_dir
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map_join(&File.read!/1)
    |> sha256()
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
