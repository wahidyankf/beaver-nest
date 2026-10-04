defmodule BnestApp.Scheduler.Domain.Policy do
  @moduledoc """
  The Scheduler's time and attempt rules: fixed-UTC daily slots and the WIB time an operator
  edits in, the claim lease and the retry waits of at most three attempts, expiration, and
  what an operator's daily edit may change. Every schedule store decides a claim, a
  recovery and a failure through these functions, so the stores differ only in how they
  persist the result. Backup's task reads its WIB calendar dates here too.
  """

  @wib_offset_seconds 7 * 60 * 60
  @lease_seconds 15 * 60
  @max_attempts 3
  @editable_handler_key "prod_sqlite_backup"

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

  @doc """
  What claiming a due schedule at `now` does. An eligible schedule claims its latest slot:
  the slot, its claim key, the occurrence it counts, the lease, the schedule's next run, and
  `now` as its expiry when that occurrence is its last (else nil). An ineligible schedule
  expires instead.
  """
  @spec claim(map(), DateTime.t()) :: {:claim, map()} | :expire
  def claim(schedule, %DateTime{} = now) do
    scheduled_for = latest_slot(schedule.daily_at_utc, now)

    if eligible?(schedule, scheduled_for) do
      occurrence = schedule.claimed_occurrences + 1

      {:claim,
       %{
         scheduled_for: scheduled_for,
         claim_key: "slot:" <> iso8601(scheduled_for),
         occurrence_number: occurrence,
         lease_expires_at: lease_until(now),
         next_run_at: next_slot(schedule.daily_at_utc, now),
         expired_at: final_occurrence_expiry(schedule, occurrence, now)
       }}
    else
      :expire
    end
  end

  @doc """
  What recovering a retryable run, or a running one whose lease expired, does: a running run
  at the last attempt fails at the attempt limit; any other runs again under the attempt
  returned (the same one when it was waiting as retryable, the next one when its lease
  expired).
  """
  @spec recovery(map()) :: :attempt_limit | {:run, pos_integer()}
  def recovery(%{state: "running", attempt: attempt}) when attempt >= @max_attempts,
    do: :attempt_limit

  def recovery(%{state: "retryable", attempt: attempt}), do: {:run, attempt}
  def recovery(%{attempt: attempt}), do: {:run, attempt + 1}

  @doc """
  What a failed attempt leads to: before the last attempt the next one waits as retryable
  until its retry time; the last attempt fails the run.
  """
  @spec after_failure(pos_integer(), DateTime.t()) ::
          {:retryable, pos_integer(), DateTime.t()} | :failed
  def after_failure(attempt, %DateTime{} = now) when attempt < @max_attempts,
    do: {:retryable, attempt + 1, retry_at(attempt, now)}

  def after_failure(_attempt, %DateTime{}), do: :failed

  @doc "The claim key of a setup run for a backup destination."
  @spec setup_claim_key(String.t()) :: String.t()
  def setup_claim_key(destination_id), do: "setup:" <> destination_id

  @doc "Whether a backup destination ID may name a setup claim."
  @spec valid_destination_id?(String.t()) :: boolean()
  def valid_destination_id?(destination_id) when is_binary(destination_id),
    do: Regex.match?(~r/^[A-Za-z0-9_-]+$/, destination_id)

  @doc """
  The daily edit an operator's form submits for `schedule`: the UTC daily time of its WIB
  time, whether it is enabled, and the revision it was read at. Only the production backup
  schedule is editable.
  """
  @spec daily_edit(map(), map()) ::
          {:ok, %{daily_at_utc: String.t(), enabled: boolean(), revision: pos_integer()}}
          | {:error, atom()}
  def daily_edit(schedule, params) do
    with true <- schedule.handler_key == @editable_handler_key || {:error, :not_editable},
         {:ok, daily_at_utc} <- wib_to_utc(Map.get(params, "daily_time_wib", "")),
         {:ok, enabled} <- parse_enabled(Map.get(params, "enabled")),
         {:ok, revision} <- parse_revision(Map.get(params, "revision")) do
      {:ok, %{daily_at_utc: daily_at_utc, enabled: enabled, revision: revision}}
    end
  end

  @doc """
  The view of a verified run that reconciliation reads: its slot (`scheduled_for`, nil for a
  setup run, which is claimed without one), when it finished and the artifact it recorded.
  Every store reports a verified run through this one projection.
  """
  @spec verified_run(map()) :: map()
  def verified_run(run) do
    %{
      run_id: run.run_id,
      slot: run.scheduled_for,
      finished_at: run.finished_at,
      artifact_basename: run.artifact_basename,
      artifact_sha256: run.artifact_sha256,
      artifact_bytes: run.artifact_bytes
    }
  end

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

  defp final_occurrence_expiry(
         %{expiration_kind: "after_occurrences", max_occurrences: max},
         occurrence,
         now
       )
       when occurrence >= max,
       do: now

  defp final_occurrence_expiry(_schedule, _occurrence, _now), do: nil

  defp parse_enabled(value) when value in [true, "true", "on", "1"], do: {:ok, true}
  defp parse_enabled(value) when value in [false, "false", "0", nil], do: {:ok, false}
  defp parse_enabled(_value), do: {:error, :invalid_enabled}

  defp parse_revision(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_revision(value) when is_binary(value) do
    case Integer.parse(value) do
      {revision, ""} when revision > 0 -> {:ok, revision}
      _invalid -> {:error, :invalid_revision}
    end
  end

  defp parse_revision(_value), do: {:error, :invalid_revision}

  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()

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
