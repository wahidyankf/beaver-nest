defmodule BnestApp.DataRepository.Import do
  @moduledoc false

  alias BnestApp.DataRepository.Backend
  alias BnestApp.DataRepository.Manifest
  alias BnestApp.DataRepository.Normalizer

  @sources %{
    {"sessionStorage", "bnest.chat.v1"} => 500_000,
    {"localStorage", "bnest.sifat-allah.v1"} => 10_000,
    {"localStorage", "phx:theme"} => 16
  }

  @spec browser(map(), String.t(), map()) :: {:ok, map()} | {:error, atom(), map() | nil}
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

  @spec absent_theme(map(), String.t()) :: {:ok, map()} | {:error, atom()}
  def absent_theme(store, owner_id) do
    case Manifest.absent_theme(store, owner_id) do
      {:ok, manifest} -> {:ok, result(manifest, nil, nil)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp begin_import(store, owner_id, area, key, payload) do
    case Manifest.pending(store, owner_id, area, key, payload) do
      {:ok, manifest} ->
        case preserve_envelope(store, owner_id, area, key, payload, manifest) do
          :ok -> {:ok, manifest}
          {:error, reason} -> fail(store, manifest, reason)
        end

      other ->
        other
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
      "integrity" => %{"sha256" => checksum, "capturedAt" => timestamp()}
    }

    case Backend.put_new(store, :browser_import, {owner_id, import_id}, envelope) do
      {:ok, _saved} -> :ok
      {:error, :exists} -> verify_existing_envelope(store, owner_id, import_id, envelope)
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  defp verify_existing_envelope(store, owner_id, import_id, expected) do
    case Backend.read(store, :browser_import, {owner_id, import_id}) do
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

    with {:ok, type, candidate} <- Normalizer.normalize(area, key, payload, import_id),
         {:ok, expected_revision} <- import_revision(store, type, owner_id, import_id),
         candidate <- Map.put(candidate, "ownerId", owner_id),
         {:ok, record} <- Backend.write(store, type, owner_id, expected_revision, candidate),
         {:ok, ^record} <- Backend.read(store, type, owner_id),
         {:ok, accepted} <- Manifest.finish(store, manifest, "accepted", nil) do
      {:ok, result(accepted, key, record)}
    else
      {:error, :malformed} -> fail(store, manifest, :malformed, "rejected")
      {:error, :stale} -> fail(store, manifest, :stale_revision)
      {:error, _reason} -> fail(store, manifest, :read_back_failed)
    end
  end

  defp rejected(store, owner_id, area, key, payload, reason) when is_binary(payload) do
    case Manifest.rejected(store, owner_id, area, key, payload, reason) do
      {:ok, manifest} -> {:error, reason, manifest}
      {:error, manifest_reason} -> {:error, manifest_reason, nil}
    end
  end

  defp rejected(_store, _owner_id, _area, _key, _payload, reason),
    do: {:error, reason, nil}

  defp fail(store, manifest, reason, status \\ "retryable") do
    case Manifest.finish(store, manifest, status, reason) do
      {:ok, failed} -> {:error, reason, failed}
      {:error, _write_reason} -> {:error, reason, manifest}
    end
  end

  defp import_revision(store, type, owner_id, import_id) do
    case Backend.read(store, type, owner_id) do
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

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
