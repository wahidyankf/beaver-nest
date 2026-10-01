defmodule BnestApp.Storage.Domain.Normalizer do
  @moduledoc """
  Turns a browser storage payload into a record candidate. Storage owns the theme preference;
  the registered record kinds own their own browser sources.
  """

  @spec normalize(String.t(), String.t(), String.t(), String.t(), String.t(), [module()]) ::
          {:ok, atom(), map()} | {:error, atom()}
  def normalize("localStorage", "phx:theme", theme, import_id, now, _kinds)
      when theme in ~w(light dark) do
    {:ok, :theme,
     %{
       "schemaVersion" => 1,
       "recordType" => "theme-preference",
       "sourceImportId" => import_id,
       "theme" => theme,
       "updatedAt" => now
     }}
  end

  def normalize("localStorage", "phx:theme", _theme, _import_id, _now, _kinds),
    do: {:error, :malformed}

  def normalize(area, key, payload, import_id, now, kinds) do
    case Enum.find(kinds, &(&1.source() == {area, key})) do
      nil -> {:error, :unsupported_source}
      kind -> normalize_kind(kind, payload, import_id, now)
    end
  end

  @spec source_version(String.t(), String.t()) :: pos_integer()
  def source_version("phx:theme", _payload), do: 1

  def source_version(_key, payload) do
    case Jason.decode(payload) do
      {:ok, %{"version" => version}} when is_integer(version) and version > 0 -> version
      _invalid -> 1
    end
  end

  defp normalize_kind(kind, payload, import_id, now) do
    with {:ok, source} <- Jason.decode(payload),
         {:ok, fields} <- kind.normalize(source) do
      base = %{
        "schemaVersion" => 1,
        "recordType" => kind.record_type(),
        "sourceImportId" => import_id,
        "updatedAt" => now
      }

      {:ok, kind.kind(), Map.merge(base, fields)}
    else
      _invalid -> {:error, :malformed}
    end
  end
end
