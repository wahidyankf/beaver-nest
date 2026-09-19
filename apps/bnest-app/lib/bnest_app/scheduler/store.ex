defmodule BnestApp.Scheduler.Store do
  @moduledoc false

  alias BnestApp.Scheduler.Policy
  alias BnestApp.SqliteRepo

  @schedule_columns ~w(
    schedule_key handler_key schedule_context cadence daily_at_utc enabled expiration_kind
    expires_at max_occurrences claimed_occurrences expired_at next_run_at revision inserted_at updated_at
  )a
  @run_columns ~w(
    schedule_key claim_key claim_kind scheduled_for run_id schedule_revision occurrence_number attempt
    state lease_expires_at next_attempt_at artifact_basename artifact_sha256 artifact_bytes failure_category
    started_at finished_at
  )a

  @spec claim_due(DateTime.t()) :: [map()]
  def claim_due(%DateTime{} = now) do
    transaction(fn ->
      now_iso = iso8601(now)

      due =
        SqliteRepo.query!(
          """
          SELECT #{columns(@schedule_columns)} FROM bnest_schedules
          WHERE enabled = 1 AND expired_at IS NULL AND next_run_at <= ?
          ORDER BY next_run_at, schedule_key
          """,
          [now_iso]
        )
        |> schedule_rows()

      scheduled_claims = Enum.flat_map(due, &claim_schedule(&1, now))
      retry_claims = claim_retries(now)
      scheduled_claims ++ retry_claims
    end)
  end

  @spec claim_setup(String.t(), String.t(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def claim_setup(schedule_key, destination_id, %DateTime{} = now)
      when is_binary(schedule_key) and is_binary(destination_id) do
    if Regex.match?(~r/^[A-Za-z0-9_-]+$/, destination_id) do
      transaction(fn ->
        schedule = get_schedule!(schedule_key)
        claim_key = setup_claim_key(destination_id)
        run_id = run_id()
        now_iso = iso8601(now)

        SqliteRepo.query!(
          """
          INSERT OR IGNORE INTO bnest_schedule_runs (
            schedule_key, claim_key, claim_kind, scheduled_for, run_id, schedule_revision,
            occurrence_number, attempt, state, lease_expires_at, next_attempt_at,
            artifact_basename, artifact_sha256, artifact_bytes, failure_category,
            started_at, finished_at
          ) VALUES (?, ?, 'setup', NULL, ?, ?, NULL, 1, 'running', ?, NULL,
                    NULL, NULL, NULL, NULL, ?, NULL)
          """,
          [
            schedule_key,
            claim_key,
            run_id,
            schedule.revision,
            iso8601(Policy.lease_until(now)),
            now_iso
          ]
        )

        {:ok, get_run!(schedule_key, claim_key)}
      end)
    else
      {:error, :invalid_destination_id}
    end
  end

  @doc false
  @spec setup_claim_key(String.t()) :: String.t()
  def setup_claim_key(destination_id), do: "setup:" <> destination_id

  @spec fail_attempt(String.t(), pos_integer(), atom(), DateTime.t()) ::
          {:retryable | :failed, map()} | {:error, :stale_attempt}
  def fail_attempt(run_id, attempt, category, %DateTime{} = now) do
    transaction(fn ->
      run = get_run_by_id!(run_id)

      if run.attempt != attempt or run.state != "running" do
        {:error, :stale_attempt}
      else
        transition_failed_attempt(run, category, now)
      end
    end)
  end

  @spec renew_lease(String.t(), pos_integer(), DateTime.t()) :: :ok | {:error, :stale_attempt}
  def renew_lease(run_id, attempt, %DateTime{} = now) do
    transaction(fn ->
      result =
        SqliteRepo.query!(
          """
          UPDATE bnest_schedule_runs SET lease_expires_at = ?
          WHERE run_id = ? AND attempt = ? AND state = 'running'
          """,
          [iso8601(Policy.lease_until(now)), run_id, attempt]
        )

      if result.num_rows == 1, do: :ok, else: {:error, :stale_attempt}
    end)
  end

  @spec active_attempt?(String.t(), pos_integer(), DateTime.t()) :: boolean()
  def active_attempt?(run_id, attempt, %DateTime{} = now) do
    %{rows: rows} =
      SqliteRepo.query!(
        """
        SELECT 1 FROM bnest_schedule_runs
        WHERE run_id = ? AND attempt = ? AND state = 'running' AND lease_expires_at > ?
        """,
        [run_id, attempt, iso8601(now)]
      )

    rows == [[1]]
  end

  @spec complete(String.t(), pos_integer(), map(), DateTime.t()) :: :ok | {:error, :stale_attempt}
  def complete(run_id, attempt, receipt, %DateTime{} = now) do
    transaction(fn ->
      result =
        SqliteRepo.query!(
          """
          UPDATE bnest_schedule_runs
          SET state = 'verified', lease_expires_at = NULL, next_attempt_at = NULL,
              artifact_basename = ?, artifact_sha256 = ?, artifact_bytes = ?,
              failure_category = NULL, finished_at = ?
          WHERE run_id = ? AND attempt = ? AND state = 'running'
          """,
          [
            receipt["artifactBasename"],
            receipt["artifactSha256"],
            receipt["artifactBytes"],
            iso8601(now),
            run_id,
            attempt
          ]
        )

      if result.num_rows == 1, do: :ok, else: {:error, :stale_attempt}
    end)
  end

  @spec skip(String.t(), pos_integer(), atom(), DateTime.t()) :: :ok | {:error, :stale_attempt}
  def skip(run_id, attempt, category, %DateTime{} = now) do
    transaction(fn ->
      result =
        SqliteRepo.query!(
          """
          UPDATE bnest_schedule_runs
          SET state = 'skipped', lease_expires_at = NULL, next_attempt_at = NULL,
              failure_category = ?, finished_at = ?
          WHERE run_id = ? AND attempt = ? AND state = 'running'
          """,
          [Atom.to_string(category), iso8601(now), run_id, attempt]
        )

      if result.num_rows == 1, do: :ok, else: {:error, :stale_attempt}
    end)
  end

  @spec get_schedule(String.t()) :: map() | nil
  def get_schedule(schedule_key) do
    case with_repo_retry(fn ->
           SqliteRepo.query!(
             "SELECT #{columns(@schedule_columns)} FROM bnest_schedules WHERE schedule_key = ?",
             [schedule_key]
           )
         end) do
      %{rows: [row]} -> schedule_row(row)
      %{rows: []} -> nil
    end
  end

  @spec run_count() :: non_neg_integer()
  def run_count do
    %{rows: [[count]]} = SqliteRepo.query!("SELECT COUNT(*) FROM bnest_schedule_runs")
    count
  end

  # Test-only seam: forces an EXISTING schedule row (seeded by a real
  # migration/reconciliation elsewhere -- never inserted here) into an
  # already-due, enabled state relative to an injected clock, so a
  # deterministic behaviour-test clock (not real wall-clock time) controls
  # whether `claim_due/1` picks it up. Mirrors `put_test_schedule/5`'s own
  # `Policy.latest_slot/2` due-relative-to-`now` pattern.
  @doc false
  @spec force_due_for_test!(String.t(), DateTime.t()) :: :ok
  def force_due_for_test!(schedule_key, %DateTime{} = now) do
    SqliteRepo.query!(
      "UPDATE bnest_schedules SET enabled = 1, next_run_at = ?, updated_at = ? WHERE schedule_key = ?",
      [iso8601(now), iso8601(now), schedule_key]
    )

    :ok
  end

  # Test-only seam: simulates "an existing (pre-plan) production schedule
  # still at its original, never-operator-edited value" -- sets
  # `daily_at_utc` directly while leaving `revision` at whatever it already
  # is, so a still-pristine (revision 1) row stays a valid CAS convergence
  # target.
  @doc false
  @spec force_daily_time_for_test!(String.t(), String.t()) :: :ok
  def force_daily_time_for_test!(schedule_key, daily_at_utc) do
    SqliteRepo.query!("UPDATE bnest_schedules SET daily_at_utc = ? WHERE schedule_key = ?", [
      daily_at_utc,
      schedule_key
    ])

    :ok
  end

  # Test-only seam: simulates a genuine operator edit's one real, durable
  # effect on CAS eligibility -- bumping `revision` -- without needing to
  # drive the full `update_daily/3` WIB-conversion/validation path from a
  # fixture.
  @doc false
  @spec force_operator_edit_for_test!(String.t(), String.t(), DateTime.t()) :: :ok
  def force_operator_edit_for_test!(schedule_key, daily_at_utc, %DateTime{} = now) do
    SqliteRepo.query!(
      "UPDATE bnest_schedules SET daily_at_utc = ?, revision = revision + 1, updated_at = ? WHERE schedule_key = ?",
      [daily_at_utc, iso8601(now), schedule_key]
    )

    :ok
  end

  # Test-only seam: several behaviour scenarios exercise different temporal
  # states (pristine-but-different-time, just-converged, operator-edited) of
  # the SAME singleton production schedule row ("prod-sqlite-backup-daily"),
  # which every unit-layer scenario in a test run shares sequentially (one
  # real SQLite database, no per-scenario transaction isolation -- see
  # learnings.md's Phase 5 entry). Seeding-if-absent alone (as
  # `PersistentSchedules.apply_and_verify!/1` does) leaves an EARLIER
  # scenario's mutation (a bumped `revision`, an edited `daily_at_utc`) in
  # place for a LATER scenario that assumes a pristine `revision = 1` start,
  # making the suite's result depend on scenario execution order. This
  # forces the row to the exact pristine precondition ("an existing schedule
  # at revision 1, using this daily time, in this enabled state") a
  # convergence-CAS scenario's `Given` describes, regardless of what any
  # earlier scenario left behind -- ordinary fixture setup, not a change to
  # what convergence itself does.
  @doc false
  @spec reset_schedule_for_test!(String.t(), String.t(), boolean(), DateTime.t()) :: :ok
  def reset_schedule_for_test!(schedule_key, daily_at_utc, enabled, %DateTime{} = now) do
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

  @spec admin_inventory() :: %{family: [map()], admin_system: [map()]}
  def admin_inventory do
    schedules = inventory_rows()

    %{
      family: Enum.filter(schedules, &(&1.schedule_context == "family")),
      admin_system: Enum.filter(schedules, &(&1.schedule_context == "admin_system"))
    }
  end

  @spec family_inventory() :: [map()]
  def family_inventory, do: Enum.filter(inventory_rows(), &(&1.schedule_context == "family"))

  @spec update_daily(String.t(), map(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def update_daily(schedule_key, params, %DateTime{} = now) do
    with %{} = schedule <- get_schedule(schedule_key),
         true <- schedule.handler_key == "prod_sqlite_backup" || {:error, :not_editable},
         {:ok, daily_at_utc} <- Policy.wib_to_utc(Map.get(params, "daily_time_wib", "")),
         {:ok, enabled} <- parse_enabled(Map.get(params, "enabled")),
         {:ok, revision} <- parse_revision(Map.get(params, "revision")) do
      transaction(fn ->
        update_daily_transaction(schedule_key, daily_at_utc, enabled, revision, now)
      end)
    else
      nil -> {:error, :unknown_schedule}
      false -> {:error, :not_editable}
      {:error, reason} -> {:error, reason}
    end
  end

  # One-time CAS convergence (see `BnestApp.Scheduler.converge_backup_time!/2`
  # for the full rationale): only ever matches a schedule row at its pristine
  # `revision = 1`, so a second call (or a call against a row an operator has
  # since edited via `update_daily/3`, which always bumps revision) is a
  # true no-op that still returns the row's current state.
  @spec converge_daily_time_if_pristine!(String.t(), String.t(), DateTime.t()) :: {:ok, map()}
  def converge_daily_time_if_pristine!(schedule_key, daily_at_utc, %DateTime{} = now) do
    transaction(fn ->
      SqliteRepo.query!(
        """
        UPDATE bnest_schedules
        SET daily_at_utc = ?, next_run_at = ?, revision = revision + 1, updated_at = ?
        WHERE schedule_key = ? AND revision = 1
        """,
        [daily_at_utc, iso8601(Policy.next_slot(daily_at_utc, now)), iso8601(now), schedule_key]
      )

      {:ok, get_schedule!(schedule_key)}
    end)
  end

  # Same CAS-on-`revision = 1` seam as `converge_daily_time_if_pristine!/3`
  # (see `BnestApp.Scheduler.converge_backup_time!/2`'s moduledoc), applied
  # to `enabled` instead of `daily_at_utc`: flips a still-pristine schedule
  # from disabled to enabled exactly once, and is a no-op once any operator
  # edit (which always bumps revision) has touched the row.
  @spec activate_if_pristine!(String.t(), DateTime.t()) :: :ok
  def activate_if_pristine!(schedule_key, %DateTime{} = now) do
    SqliteRepo.query!(
      "UPDATE bnest_schedules SET enabled = 1, revision = revision + 1, updated_at = ? WHERE schedule_key = ? AND revision = 1",
      [iso8601(now), schedule_key]
    )

    :ok
  end

  defp claim_schedule(schedule, now) do
    scheduled_for = Policy.latest_slot(schedule.daily_at_utc, now)
    next_run_at = Policy.next_slot(schedule.daily_at_utc, now)

    if Policy.eligible?(schedule, scheduled_for) do
      occurrence = schedule.claimed_occurrences + 1
      claim_key = "slot:" <> iso8601(scheduled_for)
      expired_at = final_occurrence_expiry(schedule, occurrence, now)

      inserted =
        SqliteRepo.query!(
          """
          INSERT OR IGNORE INTO bnest_schedule_runs (
            schedule_key, claim_key, claim_kind, scheduled_for, run_id, schedule_revision,
            occurrence_number, attempt, state, lease_expires_at, next_attempt_at,
            artifact_basename, artifact_sha256, artifact_bytes, failure_category,
            started_at, finished_at
          ) VALUES (?, ?, 'scheduled', ?, ?, ?, ?, 1, 'running', ?, NULL,
                    NULL, NULL, NULL, NULL, ?, NULL)
          """,
          [
            schedule.schedule_key,
            claim_key,
            iso8601(scheduled_for),
            run_id(),
            schedule.revision,
            occurrence,
            iso8601(Policy.lease_until(now)),
            iso8601(now)
          ]
        )

      if inserted.num_rows == 1 do
        SqliteRepo.query!(
          """
          UPDATE bnest_schedules
          SET claimed_occurrences = ?, expired_at = ?, next_run_at = ?, updated_at = ?
          WHERE schedule_key = ? AND revision = ?
          """,
          [
            occurrence,
            nullable_iso(expired_at),
            iso8601(next_run_at),
            iso8601(now),
            schedule.schedule_key,
            schedule.revision
          ]
        )

        [get_run!(schedule.schedule_key, claim_key)]
      else
        []
      end
    else
      SqliteRepo.query!(
        "UPDATE bnest_schedules SET expired_at = ?, updated_at = ? WHERE schedule_key = ?",
        [iso8601(now), iso8601(now), schedule.schedule_key]
      )

      []
    end
  end

  defp update_daily_transaction(schedule_key, daily_at_utc, enabled, revision, now) do
    result =
      SqliteRepo.query!(
        """
        UPDATE bnest_schedules
        SET daily_at_utc = ?, enabled = ?, next_run_at = ?, revision = revision + 1,
            updated_at = ?
        WHERE schedule_key = ? AND revision = ?
        """,
        [
          daily_at_utc,
          if(enabled, do: 1, else: 0),
          iso8601(Policy.next_slot(daily_at_utc, now)),
          iso8601(now),
          schedule_key,
          revision
        ]
      )

    if result.num_rows == 1,
      do: {:ok, get_schedule!(schedule_key)},
      else: {:error, :conflict}
  end

  defp claim_retries(now) do
    %{rows: rows} =
      SqliteRepo.query!(
        """
        SELECT #{columns(@run_columns)} FROM bnest_schedule_runs
        WHERE (state = 'retryable' AND next_attempt_at <= ?)
           OR (state = 'running' AND lease_expires_at <= ?)
        ORDER BY started_at, run_id
        """,
        [iso8601(now), iso8601(now)]
      )

    Enum.flat_map(rows, &recover_run(run_row(&1), now))
  end

  defp recover_run(%{state: "running", attempt: attempt} = run, now) when attempt >= 3 do
    SqliteRepo.query!(
      """
      UPDATE bnest_schedule_runs SET state = 'failed', lease_expires_at = NULL,
        next_attempt_at = NULL, failure_category = 'attempt_limit', finished_at = ?
      WHERE run_id = ?
      """,
      [iso8601(now), run.run_id]
    )

    []
  end

  defp recover_run(run, now) do
    next_attempt = if run.state == "retryable", do: run.attempt, else: run.attempt + 1

    SqliteRepo.query!(
      """
      UPDATE bnest_schedule_runs SET state = 'running', attempt = ?, lease_expires_at = ?,
        next_attempt_at = NULL, failure_category = NULL, started_at = ?, finished_at = NULL
      WHERE run_id = ? AND attempt = ? AND state = ?
      """,
      [
        next_attempt,
        iso8601(Policy.lease_until(now)),
        iso8601(now),
        run.run_id,
        run.attempt,
        run.state
      ]
    )

    [get_run_by_id!(run.run_id)]
  end

  defp transition_failed_attempt(run, category, now) when run.attempt < 3 do
    next_attempt = run.attempt + 1

    SqliteRepo.query!(
      """
      UPDATE bnest_schedule_runs SET state = 'retryable', attempt = ?, lease_expires_at = NULL,
        next_attempt_at = ?, failure_category = ?, finished_at = ? WHERE run_id = ?
      """,
      [
        next_attempt,
        nullable_iso(Policy.retry_at(run.attempt, now)),
        Atom.to_string(category),
        iso8601(now),
        run.run_id
      ]
    )

    {:retryable, get_run_by_id!(run.run_id)}
  end

  defp transition_failed_attempt(run, category, now) do
    SqliteRepo.query!(
      """
      UPDATE bnest_schedule_runs SET state = 'failed', lease_expires_at = NULL,
        next_attempt_at = NULL, failure_category = ?, finished_at = ? WHERE run_id = ?
      """,
      [Atom.to_string(category), iso8601(now), run.run_id]
    )

    {:failed, get_run_by_id!(run.run_id)}
  end

  defp inventory_rows do
    %{rows: rows} =
      SqliteRepo.query!("""
      SELECT #{columns(Enum.map(@schedule_columns, &("s." <> Atom.to_string(&1))))},
             r.state, r.failure_category, r.finished_at
      FROM bnest_schedules AS s
      LEFT JOIN bnest_schedule_runs AS r ON r.run_id = (
        SELECT latest.run_id FROM bnest_schedule_runs AS latest
        WHERE latest.schedule_key = s.schedule_key
        ORDER BY latest.started_at DESC, latest.run_id DESC LIMIT 1
      )
      ORDER BY s.schedule_context, s.schedule_key
      """)

    Enum.map(rows, fn row ->
      {schedule_values, [state, failure_category, finished_at]} =
        Enum.split(row, length(@schedule_columns))

      schedule_row(schedule_values)
      |> Map.put(:last_run_state, state)
      |> Map.put(:last_failure_category, failure_category)
      |> Map.put(:last_finished_at, nullable_datetime(finished_at))
    end)
  end

  defp get_schedule!(key), do: get_schedule(key) || raise("unknown schedule")

  defp get_run!(schedule_key, claim_key) do
    %{rows: [row]} =
      SqliteRepo.query!(
        "SELECT #{columns(@run_columns)} FROM bnest_schedule_runs WHERE schedule_key = ? AND claim_key = ?",
        [schedule_key, claim_key]
      )

    run_row(row)
  end

  defp get_run_by_id!(run_id) do
    %{rows: [row]} =
      SqliteRepo.query!(
        "SELECT #{columns(@run_columns)} FROM bnest_schedule_runs WHERE run_id = ?",
        [run_id]
      )

    run_row(row)
  end

  defp schedule_rows(%{rows: rows}), do: Enum.map(rows, &schedule_row/1)

  defp schedule_row(row) do
    @schedule_columns
    |> Enum.zip(row)
    |> Map.new()
    |> Map.update!(:enabled, &(&1 == 1))
    |> parse_datetime_fields([:expires_at, :expired_at, :next_run_at, :inserted_at, :updated_at])
  end

  defp run_row(row) do
    @run_columns
    |> Enum.zip(row)
    |> Map.new()
    |> parse_datetime_fields([
      :scheduled_for,
      :lease_expires_at,
      :next_attempt_at,
      :started_at,
      :finished_at
    ])
  end

  defp parse_datetime_fields(map, fields) do
    Enum.reduce(fields, map, fn field, acc ->
      Map.update!(acc, field, fn
        nil -> nil
        value -> Policy.parse_datetime!(value)
      end)
    end)
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

  defp transaction(fun) do
    with_repo_retry(fn ->
      case SqliteRepo.transaction(fun, mode: :immediate) do
        {:ok, value} -> value
        {:error, reason} -> raise "scheduler transaction failed: #{inspect(reason)}"
      end
    end)
  end

  # `SqliteRepo` is deliberately started/stopped outside OTP supervision by
  # `StorageCoordinator` (storage relocation, migration, and per-test-module
  # database isolation all call `ensure_started!/1` and `stop/0` directly --
  # see its moduledoc). `BnestApp.Scheduler`, by contrast, is a permanently
  # supervised, independently-ticking process that never pauses for that
  # swap. A `Store` call that lands in the few-millisecond window between the
  # old repo terminating and its replacement registering sees the repo as
  # transiently absent, not genuinely broken -- retry briefly (well under
  # `SqliteRepo`'s own 5s `busy_timeout` and the 1s the integration test
  # driver already budgets for a scheduler restart) before surfacing it as
  # real. Any other error -- including a real query/business-logic failure --
  # is reraised immediately, on the first attempt, unretried.
  @repo_retry_attempts 5
  @repo_retry_delay_ms 20

  defp with_repo_retry(fun), do: with_repo_retry(fun, @repo_retry_attempts)

  defp with_repo_retry(fun, 1), do: fun.()

  defp with_repo_retry(fun, attempts) do
    fun.()
  rescue
    e in RuntimeError ->
      if transient_repo_error?(e.message) do
        Process.sleep(@repo_retry_delay_ms)
        with_repo_retry(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  catch
    :exit, reason ->
      if transient_repo_error?(reason) do
        Process.sleep(@repo_retry_delay_ms)
        with_repo_retry(fun, attempts - 1)
      else
        exit(reason)
      end
  end

  defp transient_repo_error?(message) when is_binary(message),
    do: String.contains?(message, "could not lookup Ecto repo")

  defp transient_repo_error?({:shutdown, _}), do: true
  defp transient_repo_error?(:shutdown), do: true
  defp transient_repo_error?(_other), do: false

  defp columns(fields), do: Enum.map_join(fields, ", ", &to_string/1)
  defp nullable_datetime(nil), do: nil
  defp nullable_datetime(value), do: Policy.parse_datetime!(value)
  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp nullable_iso(nil), do: nil
  defp nullable_iso(value), do: iso8601(value)
  defp run_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
