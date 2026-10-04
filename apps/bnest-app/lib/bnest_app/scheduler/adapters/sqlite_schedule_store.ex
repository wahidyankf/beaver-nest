defmodule BnestApp.Scheduler.Adapters.SqliteScheduleStore do
  @moduledoc """
  The `BnestApp.Scheduler.Ports.ScheduleStore` over the `bnest_schedules` and
  `bnest_schedule_runs` tables of the shared SQLite database: raw SQL through
  `BnestApp.SqliteRepo`, every multi-statement change in an immediate transaction. The claim,
  recovery and failure decisions are `BnestApp.Scheduler.Domain.Policy`'s; this adapter
  persists them.
  """

  @behaviour BnestApp.Scheduler.Ports.ScheduleStore

  alias BnestApp.Scheduler.Domain.Policy
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

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def claim_due(_store, %DateTime{} = now) do
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

  @impl true
  def claim_setup(_store, schedule_key, claim_key, %DateTime{} = now) do
    transaction(fn ->
      schedule = get_schedule!(schedule_key)
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
          run_id(),
          schedule.revision,
          iso8601(Policy.lease_until(now)),
          now_iso
        ]
      )

      get_run!(schedule_key, claim_key)
    end)
  end

  @impl true
  def fail_attempt(_store, run_id, attempt, category, %DateTime{} = now) do
    transaction(fn ->
      run = get_run_by_id!(run_id)

      if run.attempt != attempt or run.state != "running" do
        {:error, :stale_attempt}
      else
        transition_failed_attempt(run, category, now)
      end
    end)
  end

  @impl true
  def renew_lease(_store, run_id, attempt, %DateTime{} = now) do
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

  @impl true
  def active_attempt?(_store, run_id, attempt, %DateTime{} = now) do
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

  @impl true
  def complete(_store, run_id, attempt, receipt, %DateTime{} = now) do
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

  @impl true
  def skip(_store, run_id, attempt, category, %DateTime{} = now) do
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

  @impl true
  def get_schedule(_store, schedule_key), do: get_schedule(schedule_key)

  @impl true
  def inventory(_store) do
    %{rows: rows} =
      SqliteRepo.query!("""
      SELECT #{qualified(@schedule_columns, "s")},
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

  @impl true
  def verified_runs(_store, handler_key) do
    %{rows: rows} =
      SqliteRepo.query!(
        """
        SELECT #{qualified(@run_columns, "r")}
        FROM bnest_schedule_runs AS r
        JOIN bnest_schedules AS s ON s.schedule_key = r.schedule_key
        WHERE s.handler_key = ? AND r.state = 'verified'
        ORDER BY r.finished_at, r.run_id
        """,
        [handler_key]
      )

    rows |> Enum.map(&run_row/1) |> Enum.map(&Policy.verified_run/1)
  end

  @impl true
  def update_daily(_store, schedule_key, daily_at_utc, enabled, revision, %DateTime{} = now) do
    transaction(fn ->
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
    end)
  end

  # One-time CAS convergence (see `BnestApp.Scheduler.converge_backup_time!/2`
  # for the full rationale): only ever matches a schedule row at its pristine
  # `revision = 1`, so a second call (or a call against a row an operator has
  # since edited via `update_daily/6`, which always bumps revision) is a
  # true no-op that still returns the row's current state.
  @impl true
  def converge_daily_time_if_pristine!(_store, schedule_key, daily_at_utc, %DateTime{} = now) do
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

  # Same CAS-on-`revision = 1` seam as `converge_daily_time_if_pristine!/4`
  # (see `BnestApp.Scheduler.converge_backup_time!/2`'s moduledoc), applied
  # to `enabled` instead of `daily_at_utc`: flips a still-pristine schedule
  # from disabled to enabled exactly once, and is a no-op once any operator
  # edit (which always bumps revision) has touched the row.
  @impl true
  def activate_if_pristine!(_store, schedule_key, %DateTime{} = now) do
    SqliteRepo.query!(
      "UPDATE bnest_schedules SET enabled = 1, revision = revision + 1, updated_at = ? WHERE schedule_key = ? AND revision = 1",
      [iso8601(now), schedule_key]
    )

    :ok
  end

  defp get_schedule(schedule_key) do
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

  defp claim_schedule(schedule, now) do
    case Policy.claim(schedule, now) do
      {:claim, claim} ->
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
              claim.claim_key,
              iso8601(claim.scheduled_for),
              run_id(),
              schedule.revision,
              claim.occurrence_number,
              iso8601(claim.lease_expires_at),
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
              claim.occurrence_number,
              nullable_iso(claim.expired_at),
              iso8601(claim.next_run_at),
              iso8601(now),
              schedule.schedule_key,
              schedule.revision
            ]
          )

          [get_run!(schedule.schedule_key, claim.claim_key)]
        else
          []
        end

      :expire ->
        SqliteRepo.query!(
          "UPDATE bnest_schedules SET expired_at = ?, updated_at = ? WHERE schedule_key = ?",
          [iso8601(now), iso8601(now), schedule.schedule_key]
        )

        []
    end
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

  defp recover_run(run, now) do
    case Policy.recovery(run) do
      :attempt_limit ->
        SqliteRepo.query!(
          """
          UPDATE bnest_schedule_runs SET state = 'failed', lease_expires_at = NULL,
            next_attempt_at = NULL, failure_category = 'attempt_limit', finished_at = ?
          WHERE run_id = ?
          """,
          [iso8601(now), run.run_id]
        )

        []

      {:run, next_attempt} ->
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
  end

  defp transition_failed_attempt(run, category, now) do
    case Policy.after_failure(run.attempt, now) do
      {:retryable, next_attempt, next_attempt_at} ->
        SqliteRepo.query!(
          """
          UPDATE bnest_schedule_runs SET state = 'retryable', attempt = ?, lease_expires_at = NULL,
            next_attempt_at = ?, failure_category = ?, finished_at = ? WHERE run_id = ?
          """,
          [
            next_attempt,
            nullable_iso(next_attempt_at),
            Atom.to_string(category),
            iso8601(now),
            run.run_id
          ]
        )

        {:retryable, get_run_by_id!(run.run_id)}

      :failed ->
        SqliteRepo.query!(
          """
          UPDATE bnest_schedule_runs SET state = 'failed', lease_expires_at = NULL,
            next_attempt_at = NULL, failure_category = ?, finished_at = ? WHERE run_id = ?
          """,
          [Atom.to_string(category), iso8601(now), run.run_id]
        )

        {:failed, get_run_by_id!(run.run_id)}
    end
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

  defp transaction(fun) do
    with_repo_retry(fn ->
      case SqliteRepo.transaction(fun, mode: :immediate) do
        {:ok, value} -> value
        {:error, reason} -> raise "scheduler transaction failed: #{inspect(reason)}"
      end
    end)
  end

  # `SqliteRepo` is deliberately started/stopped outside OTP supervision by
  # `Storage.Adapters.SqliteCoordinator` (storage relocation, migration, and per-test-module
  # database isolation all call `ensure_started!/1` and `stop/0` directly --
  # see its moduledoc). `BnestApp.Scheduler`, by contrast, is a permanently
  # supervised, independently-ticking process that never pauses for that
  # swap. A store call that lands in the few-millisecond window between the
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
  defp qualified(fields, table_alias), do: Enum.map_join(fields, ", ", &"#{table_alias}.#{&1}")
  defp nullable_datetime(nil), do: nil
  defp nullable_datetime(value), do: Policy.parse_datetime!(value)
  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp nullable_iso(nil), do: nil
  defp nullable_iso(value), do: iso8601(value)
  defp run_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
