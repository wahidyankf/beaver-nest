defmodule BnestApp.Test.Seeds.Schedules do
  @moduledoc """
  Test-only Scheduler rows in the SQLite database the shared `BnestApp.SqliteRepo` serves:
  the schedules a Given describes, and the run count a Then compares. The product creates
  schedules only through release seeds and changes them only through the Scheduler facade;
  these seams put a row into the exact state a scenario starts from instead. They moved here
  from the former `BnestApp.Scheduler.Store` unchanged, SQL included.
  """

  alias BnestApp.Scheduler.Domain.Policy
  alias BnestApp.SqliteRepo

  @schedule_columns ~w(
    schedule_key handler_key schedule_context cadence daily_at_utc enabled
    expiration_kind expires_at max_occurrences claimed_occurrences expired_at
    next_run_at revision inserted_at updated_at
  )a

  @doc """
  A pristine, enabled daily schedule at 19:00 UTC under the handler key, due at its latest
  slot before `now`; `max_occurrences:` makes it expire after that many claims. The FE e2e
  server seeds family schedules through this too.
  """
  @spec put_test_schedule(String.t(), String.t(), String.t(), DateTime.t(), keyword()) :: :ok
  def put_test_schedule(key, context, handler, %DateTime{} = now, options \\ []) do
    max_occurrences = Keyword.get(options, :max_occurrences)
    expiration_kind = if max_occurrences, do: "after_occurrences", else: "never"
    next_run_at = Policy.latest_slot("19:00", now)
    timestamp = iso8601(now)

    SqliteRepo.query!(
      """
      INSERT INTO bnest_schedules (
        schedule_key, handler_key, schedule_context, cadence, daily_at_utc, enabled,
        expiration_kind, expires_at, max_occurrences, claimed_occurrences, expired_at,
        next_run_at, revision, inserted_at, updated_at
      ) VALUES (?, ?, ?, 'daily', '19:00', 1, ?, NULL, ?, 0, NULL, ?, 1, ?, ?)
      """,
      [
        key,
        handler,
        context,
        expiration_kind,
        max_occurrences,
        iso8601(next_run_at),
        timestamp,
        timestamp
      ]
    )

    :ok
  end

  @doc """
  Stores a full schedule (every `bnest_schedules` column, as the
  `BnestApp.Scheduler.Ports.ScheduleStore` schedule type names them) as is, replacing a
  stored schedule with the same key.
  """
  @spec put_schedule!(map()) :: :ok
  def put_schedule!(schedule) do
    updates =
      @schedule_columns
      |> List.delete(:schedule_key)
      |> Enum.map_join(", ", &"#{&1} = excluded.#{&1}")

    SqliteRepo.query!(
      """
      INSERT INTO bnest_schedules (#{Enum.map_join(@schedule_columns, ", ", &to_string/1)})
      VALUES (#{Enum.map_join(@schedule_columns, ", ", fn _column -> "?" end)})
      ON CONFLICT (schedule_key) DO UPDATE SET #{updates}
      """,
      Enum.map(@schedule_columns, &column_value(Map.fetch!(schedule, &1)))
    )

    :ok
  end

  @doc """
  Several behaviour scenarios exercise different temporal states (pristine-but-different-
  time, just-converged, operator-edited) of the SAME singleton production schedule row
  ("prod-sqlite-backup-daily"), which every scenario of a layer shares sequentially (one
  real SQLite database, no per-scenario transaction isolation -- see learnings.md's Phase 5
  entry). Seeding-if-absent alone (as `PersistentSchedules.apply_and_verify!/1` does) leaves
  an EARLIER scenario's mutation (a bumped `revision`, an edited `daily_at_utc`) in place for
  a LATER scenario that assumes a pristine `revision = 1` start, making the suite's result
  depend on scenario execution order. This forces the row to the exact pristine
  precondition ("an existing schedule at revision 1, using this daily time, in this enabled
  state") a convergence-CAS scenario's Given describes, regardless of what any earlier
  scenario left behind -- ordinary fixture setup, not a change to what convergence itself
  does.
  """
  @spec reset_schedule!(String.t(), String.t(), boolean(), DateTime.t()) :: :ok
  def reset_schedule!(schedule_key, daily_at_utc, enabled, %DateTime{} = now) do
    next_run_at = daily_at_utc |> Policy.latest_slot(now) |> iso8601()
    timestamp = iso8601(now)
    enabled_int = if enabled, do: 1, else: 0

    SqliteRepo.query!(
      """
      INSERT INTO bnest_schedules (
        schedule_key, handler_key, schedule_context, cadence, daily_at_utc, enabled,
        expiration_kind, expires_at, max_occurrences, claimed_occurrences, expired_at,
        next_run_at, revision, inserted_at, updated_at
      ) VALUES (?, 'prod_sqlite_backup', 'admin_system', 'daily', ?, ?, 'never', NULL, NULL, 0, NULL, ?, 1, ?, ?)
      ON CONFLICT (schedule_key) DO UPDATE SET
        daily_at_utc = excluded.daily_at_utc,
        enabled = excluded.enabled,
        next_run_at = excluded.next_run_at,
        revision = 1,
        updated_at = excluded.updated_at
      """,
      [schedule_key, daily_at_utc, enabled_int, next_run_at, timestamp, timestamp]
    )

    :ok
  end

  @doc """
  Forces an EXISTING schedule row (seeded by a real migration or reconciliation elsewhere --
  never inserted here) into an already-due, enabled state relative to an injected clock, so
  a deterministic behaviour-test clock (not real wall-clock time) controls whether the
  Scheduler's due claim picks it up.
  """
  @spec force_due!(String.t(), DateTime.t()) :: :ok
  def force_due!(schedule_key, %DateTime{} = now) do
    SqliteRepo.query!(
      "UPDATE bnest_schedules SET enabled = 1, next_run_at = ?, updated_at = ? WHERE schedule_key = ?",
      [iso8601(now), iso8601(now), schedule_key]
    )

    :ok
  end

  @doc """
  Complements `force_due!/2`: a scenario that only asserts a schedule's `enabled`/`revision`
  fields (never claims it) must not leave that row due afterward -- `reset_schedule!/4`
  always seeds `next_run_at` at-or-before `now` (it computes the *latest* slot), so once such
  a scenario flips `enabled` to `1` (e.g. via `Scheduler.activate_if_pristine!/2`) the row
  becomes claimable and stays that way for whichever later scenario in this shared database
  next claims due work for an unrelated schedule -- the due claim sweeps every due+enabled
  row, not just the one it was asked about, silently stealing this row's claim before the
  scenario that actually means to claim it runs. Pushing `next_run_at` a day out removes
  the row from contention without touching `enabled`/`revision`/`daily_at_utc`.
  """
  @spec force_not_due!(String.t(), DateTime.t()) :: :ok
  def force_not_due!(schedule_key, %DateTime{} = now) do
    SqliteRepo.query!(
      "UPDATE bnest_schedules SET next_run_at = ? WHERE schedule_key = ?",
      [iso8601(DateTime.add(now, 86_400, :second)), schedule_key]
    )

    :ok
  end

  @doc """
  Simulates a genuine operator edit's one real, durable effect on CAS eligibility --
  bumping `revision` -- without driving the full `Scheduler.update_daily/3` WIB-conversion
  and validation path from a fixture.
  """
  @spec force_operator_edit!(String.t(), String.t(), DateTime.t()) :: :ok
  def force_operator_edit!(schedule_key, daily_at_utc, %DateTime{} = now) do
    SqliteRepo.query!(
      "UPDATE bnest_schedules SET daily_at_utc = ?, revision = revision + 1, updated_at = ? WHERE schedule_key = ?",
      [daily_at_utc, iso8601(now), schedule_key]
    )

    :ok
  end

  @doc "How many runs the database holds, of every schedule."
  @spec run_count() :: non_neg_integer()
  def run_count do
    %{rows: [[count]]} = SqliteRepo.query!("SELECT COUNT(*) FROM bnest_schedule_runs")
    count
  end

  defp column_value(true), do: 1
  defp column_value(false), do: 0
  defp column_value(%DateTime{} = value), do: iso8601(value)
  defp column_value(value), do: value

  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
