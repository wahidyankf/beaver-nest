defmodule BnestApp.Backup.Domain.Retention do
  @moduledoc """
  Which owned backups a destination keeps: the newest of each WIB (UTC+07:00) date, for the
  seven latest dates that hold one. Retention judges owned receipts only, so unknown files
  and other destinations are never candidates.

  The WIB date and the seven-date window are defined here once: `retained_groups/2` is the
  grouping retention keeps by and that `BnestApp.Backup.Domain.Reconciliation` expects by.
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
    |> retained_groups(&parse_utc!(&1["createdAt"]))
    |> Enum.map(fn {_date, [newest | _older]} -> newest["runId"] end)
    |> MapSet.new()
  end

  @doc """
  The items, ordered newest first, grouped by the WIB date of the instant `instant_of` reads
  from each, for the seven latest dates that hold one: `{date, items}` pairs, the latest date
  first and each date's items still newest first, so the head of a group is the one retention
  keeps for its date.
  """
  @spec retained_groups([item], (item -> DateTime.t())) :: [{Date.t(), [item, ...]}]
        when item: term()
  def retained_groups(items, instant_of) when is_function(instant_of, 1) do
    items
    |> Enum.group_by(&(&1 |> instant_of.() |> wib_date()))
    |> Enum.sort_by(fn {date, _items} -> date end, {:desc, Date})
    |> Enum.take(@retained_dates)
  end

  @doc "The calendar date of a UTC instant in WIB (UTC+07:00)."
  @spec wib_date(DateTime.t()) :: Date.t()
  def wib_date(%DateTime{} = instant),
    do: instant |> DateTime.add(@wib_offset_seconds) |> DateTime.to_date()

  defp parse_utc!(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, 0} -> parsed
      _invalid -> raise ArgumentError, "expected a UTC ISO 8601 instant"
    end
  end
end
