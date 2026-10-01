defmodule BnestApp.Storage.Import do
  @moduledoc """
  Imports one browser storage source into the record repository. The manifest tracks every
  attempt, and the original payload is kept as an import envelope, so a failed import can be
  retried and an accepted one can be recovered.
  """

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.Manifest
  alias BnestApp.Storage.Domain.Normalizer
  alias BnestApp.Storage.Ports.RecordBackend

  @sources %{
    {"sessionStorage", "bnest.chat.v1"} => 500_000,
    {"localStorage", "bnest.sifat-allah.v1"} => 10_000,
    {"localStorage", "phx:theme"} => 16
  }

  @spec browser(RecordBackend.state(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map() | nil}
  def browser(store, owner_id, source) when is_binary(owner_id) and is_map(source) do
    area = source["storageArea"]
    key = source["storageKey"]
    payload = source["payload"]

    with {:ok, limit} <- allowed(area, key),
         :ok <- valid_payload(payload, limit),
         {:ok, manifest} <- begin_import(store, owner_id, area, key, payload),
         {:ok, result} <- migrate(store, owner_id, area, key, payload, manifest) do
      {:ok, result}
    else
      {:accepted, manifest} ->
        {:ok, result(manifest, key, nil)}

      {:error, reason} when reason in [:unsupported_source, :oversized] ->
        rejected(store, owner_id, area, key, payload, reason)

      {:error, reason, manifest} ->
        {:error, reason, manifest}

      {:error, reason} ->
        {:error, reason, nil}
    end
  end

  def browser(_store, _owner_id, _source), do: {:error, :unsupported_source, nil}

  @spec absent_theme(RecordBackend.state(), String.t()) :: {:ok, map()} | {:error, atom()}
  def absent_theme(store, owner_id) do
    case put_new_or_read(store, Manifest.absent_theme(owner_id, Storage.now())) do
      {:ok, manifest} -> {:ok, result(manifest, nil, nil)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp begin_import(store, owner_id, area, key, payload) do
    case pending(store, owner_id, area, key, payload) do
      {:ok, manifest} ->
        case preserve_envelope(store, owner_id, area, key, payload, manifest) do
          :ok -> {:ok, manifest}
          {:error, reason} -> fail(store, manifest, reason)
        end

      other ->
        other
    end
  end

  defp pending(store, owner_id, area, key, payload) do
    record = Manifest.new(owner_id, area, key, payload, "pending", nil, Storage.now())

    case RecordBackend.put_new(store, :manifest, record["importId"], record) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, :exists} -> resume(store, record["importId"])
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  defp resume(store, import_id) do
    case RecordBackend.read(store, :manifest, import_id) do
      {:ok, %{"status" => "accepted"} = manifest} ->
        {:accepted, manifest}

      {:ok, manifest} ->
        store_manifest(store, Manifest.resumed(manifest, Storage.now()))

      {:error, _reason} ->
        {:error, :invalid_state}
    end
  end

  defp finish(store, manifest, status, failure),
    do: store_manifest(store, Manifest.finished(manifest, status, failure, Storage.now()))

  defp store_manifest(store, manifest) do
    case RecordBackend.replace(store, :manifest, manifest["importId"], manifest) do
      {:ok, result} -> {:ok, result}
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  defp put_new_or_read(store, manifest) do
    case RecordBackend.put_new(store, :manifest, manifest["importId"], manifest) do
      {:ok, saved} -> {:ok, saved}
      {:error, :exists} -> RecordBackend.read(store, :manifest, manifest["importId"])
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  defp preserve_envelope(store, owner_id, area, key, payload, manifest) do
    import_id = manifest["importId"]
    {_id, checksum} = Manifest.identity(owner_id, area, key, payload)

    envelope = %{
      "schemaVersion" => 1,
      "recordType" => "browser-import",
      "importId" => import_id,
      "ownerId" => owner_id,
      "source" => %{
        "kind" => "browser-storage",
        "storageArea" => area,
        "storageKey" => key,
        "sourceSchemaVersion" => Normalizer.source_version(key, payload)
      },
      "payloadEncoding" => "utf8-string",
      "payload" => payload,
      "integrity" => %{"sha256" => checksum, "capturedAt" => Storage.now()}
    }

    case RecordBackend.put_new(store, :browser_import, {owner_id, import_id}, envelope) do
      {:ok, _saved} -> :ok
      {:error, :exists} -> verify_existing_envelope(store, owner_id, import_id, envelope)
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  defp verify_existing_envelope(store, owner_id, import_id, expected) do
    case RecordBackend.read(store, :browser_import, {owner_id, import_id}) do
      {:ok, ^expected} ->
        :ok

      {:ok, existing} ->
        if existing["payload"] == expected["payload"] and
             existing["integrity"]["sha256"] == expected["integrity"]["sha256"],
           do: :ok,
           else: {:error, :write_failed}

      {:error, _reason} ->
        {:error, :write_failed}
    end
  end

  defp migrate(store, owner_id, area, key, payload, manifest) do
    import_id = manifest["importId"]
    kinds = Storage.record_kinds()

    with {:ok, type, candidate} <-
           Normalizer.normalize(area, key, payload, import_id, Storage.now(), kinds),
         {:ok, expected_revision} <- import_revision(store, type, owner_id, import_id),
         candidate <- Map.put(candidate, "ownerId", owner_id),
         {:ok, record} <-
           RecordBackend.write(store, type, owner_id, expected_revision, candidate),
         {:ok, ^record} <- RecordBackend.read(store, type, owner_id),
         {:ok, accepted} <- finish(store, manifest, "accepted", nil) do
      {:ok, result(accepted, key, record)}
    else
      {:error, :malformed} -> fail(store, manifest, :malformed, "rejected")
      {:error, :stale} -> fail(store, manifest, :stale_revision)
      {:error, _reason} -> fail(store, manifest, :read_back_failed)
    end
  end

  defp rejected(store, owner_id, area, key, payload, reason) when is_binary(payload) do
    manifest = Manifest.new(owner_id, area, key, payload, "rejected", reason, Storage.now())

    case put_new_or_read(store, manifest) do
      {:ok, manifest} -> {:error, reason, manifest}
      {:error, manifest_reason} -> {:error, manifest_reason, nil}
    end
  end

  defp rejected(_store, _owner_id, _area, _key, _payload, reason),
    do: {:error, reason, nil}

  defp fail(store, manifest, reason, status \\ "retryable") do
    case finish(store, manifest, status, reason) do
      {:ok, failed} -> {:error, reason, failed}
      {:error, _write_reason} -> {:error, reason, manifest}
    end
  end

  defp import_revision(store, type, owner_id, import_id) do
    case RecordBackend.read(store, type, owner_id) do
      {:error, :missing} -> {:ok, nil}
      {:ok, %{"sourceImportId" => ^import_id, "revision" => revision}} -> {:ok, revision}
      {:ok, _newer_or_other_source} -> {:error, :stale}
      {:error, _reason} -> {:error, :read_back_failed}
    end
  end

  defp allowed(area, key) do
    case Map.fetch(@sources, {area, key}) do
      {:ok, limit} -> {:ok, limit}
      :error -> {:error, :unsupported_source}
    end
  end

  defp valid_payload(payload, limit) when is_binary(payload) do
    if byte_size(payload) <= limit, do: :ok, else: {:error, :oversized}
  end

  defp valid_payload(_payload, _limit), do: {:error, :unsupported_source}

  defp result(manifest, key, record) do
    %{
      import_id: manifest["importId"],
      status: :accepted,
      cleanup: %{"storageKey" => key},
      record: record
    }
  end
end
