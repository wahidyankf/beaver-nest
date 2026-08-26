defmodule BnestApp.DataRepository.Normalizer do
  @moduledoc false

  alias BnestApp.Chat
  alias BnestApp.DataRepository.Schema
  alias BnestApp.SifatAllah

  @spec normalize(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, atom(), map()} | {:error, atom()}
  def normalize("sessionStorage", "bnest.chat.v1", payload, import_id) do
    with {:ok, source} <- Jason.decode(payload),
         {:ok, chat} <- Chat.restore(source),
         {:ok, state} <- Chat.snapshot(chat) do
      {:ok, :chat,
       %{
         "schemaVersion" => 1,
         "recordType" => "chat",
         "sourceImportId" => import_id,
         "state" => state,
         "updatedAt" => timestamp()
       }}
    else
      _invalid -> {:error, :malformed}
    end
  end

  def normalize("localStorage", "bnest.sifat-allah.v1", payload, import_id) do
    with {:ok, source} <- Jason.decode(payload),
         {:ok, progress} <- SifatAllah.restore(source) do
      candidate = learning_candidate(progress, source["session"], import_id)
      {:ok, :sifat_allah, candidate}
    else
      _invalid -> {:error, :malformed}
    end
  end

  def normalize("localStorage", "phx:theme", theme, import_id) when theme in ~w(light dark) do
    {:ok, :theme,
     %{
       "schemaVersion" => 1,
       "recordType" => "theme-preference",
       "sourceImportId" => import_id,
       "theme" => theme,
       "updatedAt" => timestamp()
     }}
  end

  def normalize("localStorage", "phx:theme", _theme, _import_id), do: {:error, :malformed}
  def normalize(_area, _key, _payload, _import_id), do: {:error, :unsupported_source}

  @spec source_version(String.t(), String.t()) :: pos_integer()
  def source_version("phx:theme", _payload), do: 1

  def source_version(_key, payload) do
    case Jason.decode(payload) do
      {:ok, %{"version" => version}} when is_integer(version) and version > 0 -> version
      _invalid -> 1
    end
  end

  defp learning_candidate(progress, session, import_id) do
    base = %{
      "schemaVersion" => 1,
      "recordType" => "sifat-allah-progress",
      "sourceImportId" => import_id,
      "progress" => progress,
      "session" => session || %{"mode" => "dashboard"},
      "updatedAt" => timestamp()
    }

    provisional = base |> Map.put("ownerId", "user-provisional") |> Map.put("revision", 0)

    case Schema.validate(provisional) do
      {:ok, _record} -> base
      {:error, _reason} -> Map.put(base, "session", %{"mode" => "dashboard"})
    end
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
