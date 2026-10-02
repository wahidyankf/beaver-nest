defmodule BnestApp.Backup.Domain.Retention do
  @moduledoc """
  Which owned backups a destination keeps: the newest of each WIB (UTC+07:00) date, for the
  seven latest dates that hold one. Retention judges owned receipts only, so unknown files
  and other destinations are never candidates.
  """

  @retained_dates 7
  @wib_offset_seconds 7 * 60 * 60

  @doc "Orders owned receipts newest first."
  @spec newest_first([map()]) :: [map()]
  def newest_first(receipts), do: Enum.sort_by(receipts, & &1["createdAt"], :desc)

  @doc """
  The run IDs of the receipts retention keeps, from receipts ordered newest first: for each
  of the seven latest WIB dates, the first receipt of that date.
  """
  @spec retained_run_ids([map()]) :: MapSet.t(String.t())
  def retained_run_ids(receipts) do
    receipts
    |> Enum.group_by(&(&1["createdAt"] |> parse_utc!() |> wib_date()))
    |> Enum.sort_by(fn {date, _receipts} -> date end, {:desc, Date})
    |> Enum.take(@retained_dates)
    |> Enum.map(fn {_date, [newest | _older]} -> newest["runId"] end)
    |> MapSet.new()
  end

  defp wib_date(%DateTime{} = instant),
    do: instant |> DateTime.add(@wib_offset_seconds) |> DateTime.to_date()

  defp parse_utc!(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, 0} -> parsed
      _invalid -> raise ArgumentError, "expected a UTC ISO 8601 instant"
    end
  end
end
