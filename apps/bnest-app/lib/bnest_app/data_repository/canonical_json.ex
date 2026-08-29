defmodule BnestApp.DataRepository.CanonicalJson do
  @moduledoc false

  @spec encode(map()) :: String.t()
  def encode(record) when is_map(record), do: encode_value(record)

  @spec sha256(map()) :: String.t()
  def sha256(record) when is_map(record) do
    record |> encode() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp encode_value(value) when is_map(value) do
    pairs =
      value
      |> Enum.sort_by(fn {key, _val} -> key end)
      |> Enum.map(fn {key, val} -> Jason.encode!(to_string(key)) <> ":" <> encode_value(val) end)

    "{" <> Enum.join(pairs, ",") <> "}"
  end

  defp encode_value(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &encode_value/1) <> "]"
  end

  defp encode_value(value), do: Jason.encode!(value)
end
