defmodule BnestApp.Storage.Adapters.SqliteRecordBackend do
  @moduledoc false

  @behaviour BnestApp.Storage.Ports.RecordBackend

  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.CanonicalJson
  alias BnestApp.Storage.Domain.RecordMap
  alias BnestApp.Storage.Domain.RecordSchema

  import Ecto.Query

  @type t :: %{backend: module(), repo: module()}

  @spec new(module()) :: t()
  def new(repo \\ SqliteRepo), do: %{backend: __MODULE__, repo: repo}

  @spec read(t(), atom(), term()) :: {:ok, map()} | {:error, atom()}
  def read(store, type, identity) do
    with {:ok, %{record_type: record_type, record_key: record_key}} <-
           RecordMap.identity_for(type, identity),
         %{payload_json: payload} <- fetch_row(store, record_type, record_key),
         {:ok, record} <- Jason.decode(payload),
         {:ok, ^record} <- RecordSchema.validate(record, Storage.record_kinds()) do
      {:ok, record}
    else
      nil -> {:error, :missing}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_schema}
    end
  end

  @spec put_new(t(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def put_new(store, type, identity, candidate) do
    with {:ok, ids} <- RecordMap.identity_for(type, identity),
         {:ok, ^candidate} <- RecordSchema.validate(candidate, Storage.record_kinds()) do
      if fetch_row(store, ids.record_type, ids.record_key) do
        {:error, :exists}
      else
        upsert(store, ids, candidate)
        {:ok, candidate}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec replace(t(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def replace(store, type, identity, candidate) do
    with {:ok, ids} <- RecordMap.identity_for(type, identity),
         {:ok, ^candidate} <- RecordSchema.validate(candidate, Storage.record_kinds()) do
      if fetch_row(store, ids.record_type, ids.record_key) do
        upsert(store, ids, candidate)
        {:ok, candidate}
      else
        {:error, :missing}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec write(t(), atom(), term(), non_neg_integer() | nil, map()) ::
          {:ok, map()} | {:error, atom()}
  def write(store, type, identity, expected_revision, candidate) do
    with {:ok, ids} <- RecordMap.identity_for(type, identity) do
      existing = fetch_row(store, ids.record_type, ids.record_key)

      with :ok <- revision_matches(existing, expected_revision),
           prepared <- Map.put(candidate, "revision", (existing && existing.revision + 1) || 0),
           {:ok, ^prepared} <- RecordSchema.validate(prepared, Storage.record_kinds()) do
        upsert(store, ids, prepared)
        {:ok, prepared}
      else
        {:error, :stale} -> {:error, :stale}
        _invalid -> {:error, :invalid_schema}
      end
    end
  end

  @spec remove_exact(t(), atom(), term(), map()) :: :ok | {:error, atom()}
  def remove_exact(store, type, identity, expected) do
    case read(store, type, identity) do
      {:ok, ^expected} ->
        {:ok, ids} = RecordMap.identity_for(type, identity)

        from(r in "bnest_records",
          where: r.record_type == ^ids.record_type and r.record_key == ^ids.record_key
        )
        |> store.repo.delete_all()

        :ok

      {:ok, _other} ->
        {:error, :changed}

      {:error, :missing} ->
        :ok

      {:error, _reason} ->
        {:error, :invalid_schema}
    end
  end

  defp fetch_row(store, record_type, record_key) do
    from(r in "bnest_records",
      where: r.record_type == ^record_type and r.record_key == ^record_key,
      select: %{payload_json: r.payload_json, revision: r.revision}
    )
    |> store.repo.one()
  end

  defp revision_matches(nil, nil), do: :ok
  defp revision_matches(%{revision: revision}, revision), do: :ok
  defp revision_matches(_existing, _expected), do: {:error, :stale}

  defp upsert(store, ids, record) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    payload = Jason.encode!(record)
    checksum = CanonicalJson.sha256(record)

    store.repo.insert_all(
      "bnest_records",
      [
        %{
          record_type: ids.record_type,
          record_key: ids.record_key,
          owner_id: ids[:owner_id],
          schema_version: record["schemaVersion"],
          revision: record["revision"],
          payload_json: payload,
          payload_sha256: checksum,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict:
        {:replace,
         [:owner_id, :schema_version, :revision, :payload_json, :payload_sha256, :updated_at]},
      conflict_target: [:record_type, :record_key]
    )

    :ok
  end
end
