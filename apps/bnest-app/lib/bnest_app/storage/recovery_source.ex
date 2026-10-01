defmodule BnestApp.Storage.RecoverySource do
  @moduledoc false

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.Normalizer
  alias BnestApp.Storage.Ports.RecordBackend

  @spec normalize_browser(RecordBackend.state(), String.t(), String.t()) ::
          {:ok, atom(), map()} | {:error, atom()}
  def normalize_browser(store, owner_id, import_id) do
    with {:ok, envelope} <- RecordBackend.read(store, :browser_import, {owner_id, import_id}),
         :ok <- verify_envelope(envelope),
         source <- envelope["source"] do
      Normalizer.normalize(
        source["storageArea"],
        source["storageKey"],
        envelope["payload"],
        import_id,
        Storage.now(),
        Storage.record_kinds()
      )
    end
  end

  @spec verify_envelope(map()) :: :ok | {:error, atom()}
  def verify_envelope(%{"payload" => payload, "integrity" => %{"sha256" => expected}})
      when is_binary(payload) and is_binary(expected) do
    if digest(payload) == expected, do: :ok, else: {:error, :checksum_mismatch}
  end

  def verify_envelope(_envelope), do: {:error, :invalid_schema}

  defp digest(payload), do: :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
end
