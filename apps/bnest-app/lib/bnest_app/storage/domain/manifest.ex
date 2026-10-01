defmodule BnestApp.Storage.Domain.Manifest do
  @moduledoc """
  The import manifest: one record per browser source and owner that tracks the import's
  attempts and outcome. Every function here only builds records; `BnestApp.Storage.Import`
  stores them.
  """

  @spec identity(String.t(), String.t(), String.t(), String.t()) :: {String.t(), String.t()}
  def identity(owner_id, storage_area, storage_key, payload) do
    checksum = digest(payload)
    material = Enum.join([owner_id, storage_area, storage_key, checksum], "\0")

    suffix =
      :crypto.hash(:sha256, material) |> binary_part(0, 18) |> Base.url_encode64(padding: false)

    {"import-#{suffix}", checksum}
  end

  @doc "A new manifest for the source in the given status, started at `now`."
  @spec new(String.t(), String.t(), String.t(), String.t(), String.t(), atom() | nil, String.t()) ::
          map()
  def new(owner_id, storage_area, storage_key, payload, status, failure, now) do
    {import_id, checksum} = identity(owner_id, storage_area, storage_key, payload)

    %{
      "schemaVersion" => 1,
      "recordType" => "import-manifest",
      "importId" => import_id,
      "ownerId" => owner_id,
      "source" => %{
        "kind" => "browser-storage",
        "reference" => storage_key,
        "sha256" => checksum
      },
      "destination" => destination(storage_key),
      "recoverySource" => %{
        "kind" => "import-envelope",
        "relativePathTemplate" => "users/<owner-id>/imports/<import-id>.json#payload",
        "sha256" => checksum
      },
      "status" => status,
      "attempt" => 1,
      "startedAt" => now,
      "completedAt" => if(status == "pending", do: nil, else: now),
      "failureCategory" => failure_name(failure)
    }
  end

  @doc "The accepted manifest that records an owner without a browser theme preference."
  @spec absent_theme(String.t(), String.t()) :: map()
  def absent_theme(owner_id, now) do
    owner_id
    |> new("localStorage", "phx:theme", "", "accepted", nil, now)
    |> put_in(["recoverySource", "kind"], "browser-absence")
    |> put_in(["recoverySource", "relativePathTemplate"], "browser/localStorage/phx:theme")
  end

  @doc "The manifest of another attempt at an unfinished import."
  @spec resumed(map(), String.t()) :: map()
  def resumed(manifest, now) do
    %{
      manifest
      | "status" => "pending",
        "attempt" => manifest["attempt"] + 1,
        "startedAt" => now,
        "completedAt" => nil,
        "failureCategory" => nil
    }
  end

  @doc "The manifest closed in `status`, or still open when `status` is pending."
  @spec finished(map(), String.t(), atom() | nil, String.t()) :: map()
  def finished(manifest, status, failure, now) do
    %{
      manifest
      | "status" => status,
        "failureCategory" => failure_name(failure),
        "completedAt" => if(status == "pending", do: nil, else: now)
    }
  end

  defp destination(source) do
    {record_type, template} = destination_of(source)
    %{"recordType" => record_type, "relativePathTemplate" => template}
  end

  defp destination_of("bnest.chat.v1"), do: {"chat", "users/<owner-id>/chat/current.json"}

  defp destination_of("bnest.sifat-allah.v1"),
    do: {"sifat-allah-progress", "users/<owner-id>/sifat-allah/progress.json"}

  defp destination_of("phx:theme"),
    do: {"theme-preference", "users/<owner-id>/preferences/theme.json"}

  defp destination_of(_unknown), do: {"none", "none"}

  defp digest(payload), do: :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  defp failure_name(nil), do: nil
  defp failure_name(failure), do: failure |> Atom.to_string() |> String.replace("_", "-")
end
