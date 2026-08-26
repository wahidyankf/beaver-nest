defmodule BnestApp.DataRepository.Manifest do
  @moduledoc false

  alias BnestApp.DataRepository.Store

  @spec identity(String.t(), String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def identity(owner_id, storage_area, storage_key, payload) do
    checksum = digest(payload)
    material = Enum.join([owner_id, storage_area, storage_key, checksum], "\0")

    suffix =
      :crypto.hash(:sha256, material) |> binary_part(0, 18) |> Base.url_encode64(padding: false)

    {"import-#{suffix}", checksum}
  end

  @spec pending(map(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:accepted, map()} | {:error, atom()}
  def pending(store, owner_id, storage_area, storage_key, payload) do
    {import_id, checksum} = identity(owner_id, storage_area, storage_key, payload)
    record = record(import_id, owner_id, storage_key, checksum, "pending", 1, nil)

    case Store.put_new(store, :manifest, import_id, record) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, :exists} -> resume(store, record)
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  @spec finish(map(), map(), String.t(), atom() | nil) :: {:ok, map()} | {:error, atom()}
  def finish(store, manifest, status, failure) do
    completed_at = if status == "pending", do: nil, else: timestamp()

    updated = %{
      manifest
      | "status" => status,
        "failureCategory" => failure_name(failure),
        "completedAt" => completed_at
    }

    case Store.replace(store, :manifest, manifest["importId"], updated) do
      {:ok, result} -> {:ok, result}
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  @spec rejected(map(), String.t(), String.t(), String.t(), String.t(), atom()) ::
          {:ok, map()} | {:error, atom()}
  def rejected(store, owner_id, storage_area, storage_key, payload, failure) do
    {import_id, checksum} = identity(owner_id, storage_area, storage_key, payload)
    record = record(import_id, owner_id, storage_key, checksum, "rejected", 1, failure)

    case Store.put_new(store, :manifest, import_id, record) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, :exists} -> Store.read(store, :manifest, import_id)
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  @spec absent_theme(map(), String.t()) :: {:ok, map()} | {:error, atom()}
  def absent_theme(store, owner_id) do
    {import_id, checksum} = identity(owner_id, "localStorage", "phx:theme", "")

    record =
      import_id
      |> record(owner_id, "phx:theme", checksum, "accepted", 1, nil)
      |> put_in(["recoverySource", "kind"], "browser-absence")
      |> put_in(["recoverySource", "relativePathTemplate"], "browser/localStorage/phx:theme")

    case Store.put_new(store, :manifest, import_id, record) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, :exists} -> Store.read(store, :manifest, import_id)
      {:error, _reason} -> {:error, :write_failed}
    end
  end

  defp resume(store, expected) do
    import_id = expected["importId"]

    case Store.read(store, :manifest, import_id) do
      {:ok, %{"status" => "accepted"} = manifest} ->
        {:accepted, manifest}

      {:ok, manifest} ->
        resumed = %{
          manifest
          | "status" => "pending",
            "attempt" => manifest["attempt"] + 1,
            "startedAt" => timestamp(),
            "completedAt" => nil,
            "failureCategory" => nil
        }

        case Store.replace(store, :manifest, import_id, resumed) do
          {:ok, result} -> {:ok, result}
          {:error, _reason} -> {:error, :write_failed}
        end

      {:error, _reason} ->
        {:error, :invalid_state}
    end
  end

  defp record(import_id, owner_id, source, checksum, status, attempt, failure) do
    destination = destination(source)

    %{
      "schemaVersion" => 1,
      "recordType" => "import-manifest",
      "importId" => import_id,
      "ownerId" => owner_id,
      "source" => %{"kind" => "browser-storage", "reference" => source, "sha256" => checksum},
      "destination" => %{
        "recordType" => elem(destination, 0),
        "relativePathTemplate" => elem(destination, 1)
      },
      "recoverySource" => %{
        "kind" => "import-envelope",
        "relativePathTemplate" => "users/<owner-id>/imports/<import-id>.json#payload",
        "sha256" => checksum
      },
      "status" => status,
      "attempt" => attempt,
      "startedAt" => timestamp(),
      "completedAt" => if(status == "pending", do: nil, else: timestamp()),
      "failureCategory" => failure_name(failure)
    }
  end

  defp destination("bnest.chat.v1"), do: {"chat", "users/<owner-id>/chat/current.json"}

  defp destination("bnest.sifat-allah.v1"),
    do: {"sifat-allah-progress", "users/<owner-id>/sifat-allah/progress.json"}

  defp destination("phx:theme"),
    do: {"theme-preference", "users/<owner-id>/preferences/theme.json"}

  defp destination(_unknown), do: {"none", "none"}

  defp digest(payload), do: :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  defp failure_name(nil), do: nil
  defp failure_name(failure), do: failure |> Atom.to_string() |> String.replace("_", "-")
  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
