defmodule BnestApp.Scheduler.Policy do
  @moduledoc false

  @wib_offset_seconds 7 * 60 * 60
  @lease_seconds 15 * 60

  @spec latest_slot(String.t(), DateTime.t()) :: DateTime.t()
  def latest_slot(daily_at_utc, %DateTime{} = now) do
    candidate = slot_on(DateTime.to_date(now), daily_at_utc)

    if DateTime.compare(candidate, now) == :gt,
      do: DateTime.add(candidate, -86_400),
      else: candidate
  end

  @spec next_slot(String.t(), DateTime.t()) :: DateTime.t()
  def next_slot(daily_at_utc, %DateTime{} = now) do
    candidate = slot_on(DateTime.to_date(now), daily_at_utc)

    if DateTime.compare(candidate, now) == :gt,
      do: candidate,
      else: DateTime.add(candidate, 86_400)
  end

  @spec wib_to_utc(String.t()) :: {:ok, String.t()} | {:error, :invalid_time}
  def wib_to_utc(value) do
    with {:ok, time} <- parse_time(value) do
      {seconds_after_midnight, _microseconds} = Time.to_seconds_after_midnight(time)
      seconds = seconds_after_midnight - @wib_offset_seconds
      seconds = Integer.mod(seconds, 86_400)
      {:ok, seconds |> Time.from_seconds_after_midnight() |> Calendar.strftime("%H:%M")}
    end
  end

  @spec lease_until(DateTime.t()) :: DateTime.t()
  def lease_until(%DateTime{} = now), do: DateTime.add(now, @lease_seconds)

  @spec retry_at(pos_integer(), DateTime.t()) :: DateTime.t() | nil
  def retry_at(1, %DateTime{} = now), do: DateTime.add(now, 5 * 60)
  def retry_at(2, %DateTime{} = now), do: DateTime.add(now, 30 * 60)
  def retry_at(_attempt, %DateTime{}), do: nil

  @spec eligible?(map(), DateTime.t()) :: boolean()
  def eligible?(%{expiration_kind: "never"}, %DateTime{}), do: true

  def eligible?(%{expiration_kind: "at", expires_at: expires_at}, %DateTime{} = now) do
    DateTime.compare(parse_datetime!(expires_at), now) == :gt
  end

  def eligible?(
        %{
          expiration_kind: "after_occurrences",
          claimed_occurrences: claimed,
          max_occurrences: max
        },
        %DateTime{}
      ),
      do: claimed < max

  def eligible?(_schedule, %DateTime{}), do: false

  @spec wib_date(DateTime.t()) :: Date.t()
  def wib_date(%DateTime{} = instant),
    do: instant |> DateTime.add(@wib_offset_seconds) |> DateTime.to_date()

  @spec parse_datetime!(DateTime.t() | String.t()) :: DateTime.t()
  def parse_datetime!(%DateTime{} = value), do: value

  def parse_datetime!(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, 0} -> parsed
      _invalid -> raise ArgumentError, "expected a UTC ISO 8601 instant"
    end
  end

  defp slot_on(date, daily_at_utc) do
    {:ok, time} = parse_time(daily_at_utc)
    DateTime.new!(date, time, "Etc/UTC")
  end

  defp parse_time(value) when is_binary(value) do
    with true <- Regex.match?(~r/^\d{2}:\d{2}$/, value),
         {:ok, time} <- Time.from_iso8601(value <> ":00") do
      {:ok, time}
    else
      _invalid -> {:error, :invalid_time}
    end
  end

  defp parse_time(_value), do: {:error, :invalid_time}
end
