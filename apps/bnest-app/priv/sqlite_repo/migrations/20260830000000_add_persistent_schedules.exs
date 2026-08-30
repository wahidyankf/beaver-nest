defmodule BnestApp.SqliteRepo.Migrations.AddPersistentSchedules do
  @moduledoc false

  use Ecto.Migration

  def up do
    execute """
            CREATE TABLE bnest_schedules (
              schedule_key TEXT PRIMARY KEY,
              handler_key TEXT NOT NULL,
              schedule_context TEXT NOT NULL CHECK
                (schedule_context IN ('family', 'admin_system')),
              cadence TEXT NOT NULL CHECK (cadence = 'daily'),
              daily_at_utc TEXT NOT NULL CHECK
                (daily_at_utc GLOB '[0-2][0-9]:[0-5][0-9]'),
              enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
              expiration_kind TEXT NOT NULL CHECK
                (expiration_kind IN ('never', 'at', 'after_occurrences')),
              expires_at TEXT,
              max_occurrences INTEGER CHECK
                (max_occurrences IS NULL OR max_occurrences > 0),
              claimed_occurrences INTEGER NOT NULL CHECK (claimed_occurrences >= 0),
              expired_at TEXT,
              next_run_at TEXT NOT NULL,
              revision INTEGER NOT NULL CHECK (revision >= 1),
              inserted_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              CHECK (
                (expiration_kind = 'never' AND expires_at IS NULL AND max_occurrences IS NULL) OR
                (expiration_kind = 'at' AND expires_at IS NOT NULL AND max_occurrences IS NULL) OR
                (expiration_kind = 'after_occurrences' AND expires_at IS NULL AND max_occurrences IS NOT NULL)
              )
            )
            """,
            "DROP TABLE bnest_schedules"

    execute """
            CREATE TABLE bnest_schedule_runs (
              schedule_key TEXT NOT NULL REFERENCES bnest_schedules(schedule_key),
              claim_key TEXT NOT NULL,
              claim_kind TEXT NOT NULL CHECK (claim_kind IN ('scheduled', 'setup')),
              scheduled_for TEXT,
              run_id TEXT NOT NULL UNIQUE,
              schedule_revision INTEGER NOT NULL CHECK (schedule_revision >= 1),
              occurrence_number INTEGER CHECK
                (occurrence_number IS NULL OR occurrence_number >= 1),
              attempt INTEGER NOT NULL CHECK (attempt >= 1),
              state TEXT NOT NULL CHECK
                (state IN ('running','retryable','verified','failed','skipped')),
              lease_expires_at TEXT,
              next_attempt_at TEXT,
              artifact_basename TEXT,
              artifact_sha256 TEXT,
              artifact_bytes INTEGER CHECK (artifact_bytes IS NULL OR artifact_bytes >= 0),
              failure_category TEXT,
              started_at TEXT NOT NULL,
              finished_at TEXT,
              PRIMARY KEY (schedule_key, claim_key),
              CHECK (
                (claim_kind = 'scheduled' AND claim_key = 'slot:' || scheduled_for AND
                  scheduled_for IS NOT NULL AND occurrence_number IS NOT NULL) OR
                (claim_kind = 'setup' AND claim_key LIKE 'setup:%' AND
                  scheduled_for IS NULL AND occurrence_number IS NULL)
              )
            )
            """,
            "DROP TABLE bnest_schedule_runs"

    execute "CREATE INDEX bnest_schedules_due_idx ON bnest_schedules(enabled, expired_at, next_run_at)",
            "DROP INDEX bnest_schedules_due_idx"

    execute "CREATE INDEX bnest_schedules_context_idx ON bnest_schedules(schedule_context, schedule_key)",
            "DROP INDEX bnest_schedules_context_idx"

    execute "CREATE INDEX bnest_schedules_expiry_idx ON bnest_schedules(expired_at, expiration_kind, expires_at)",
            "DROP INDEX bnest_schedules_expiry_idx"

    execute "CREATE INDEX bnest_schedule_runs_retry_idx ON bnest_schedule_runs(state, next_attempt_at, lease_expires_at)",
            "DROP INDEX bnest_schedule_runs_retry_idx"
  end

  def down do
    %{rows: [[schedule_count]]} = repo().query!("SELECT COUNT(*) FROM bnest_schedules")
    %{rows: [[run_count]]} = repo().query!("SELECT COUNT(*) FROM bnest_schedule_runs")

    if schedule_count > 0 or run_count > 0 do
      raise "persistent schedules migration refuses to reverse once schedule records exist"
    end

    execute "DROP INDEX bnest_schedule_runs_retry_idx"
    execute "DROP INDEX bnest_schedules_expiry_idx"
    execute "DROP INDEX bnest_schedules_context_idx"
    execute "DROP INDEX bnest_schedules_due_idx"
    execute "DROP TABLE bnest_schedule_runs"
    execute "DROP TABLE bnest_schedules"
  end
end
