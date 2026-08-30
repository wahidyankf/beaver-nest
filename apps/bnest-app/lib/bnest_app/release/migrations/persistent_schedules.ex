defmodule BnestApp.Release.Migrations.PersistentSchedules do
  @moduledoc false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.Scheduler.Policy
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Lock

  @version 20_260_830_000_000
  @schedule_key "prod-sqlite-backup-daily"
  @required_objects ~w(
    bnest_schedules
    bnest_schedule_runs
    bnest_schedules_due_idx
    bnest_schedules_context_idx
    bnest_schedules_expiry_idx
    bnest_schedule_runs_retry_idx
  )

  @spec apply_and_verify!(DateTime.t()) :: :ok
  def apply_and_verify!(%DateTime{} = now) do
    if is_nil(Process.whereis(SqliteRepo)), do: StorageCoordinator.ensure_started!()

    Lock.with_exclusive(fn ->
      Ecto.Migrator.run(SqliteRepo, migrations_path(), :up, all: true)
      reconcile_seed!(now)
      verify!()
    end)
  end

  @spec rollback!() :: no_return() | [integer()]
  def rollback! do
    Ecto.Migrator.run(SqliteRepo, migrations_path(), :down, step: 1)
  end

  defp reconcile_seed!(now) do
    timestamp = iso8601(now)
    next_run_at = "19:00" |> Policy.latest_slot(now) |> iso8601()

    SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO bnest_schedules (
        schedule_key, handler_key, schedule_context, cadence, daily_at_utc, enabled,
        expiration_kind, expires_at, max_occurrences, claimed_occurrences, expired_at,
        next_run_at, revision, inserted_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        @schedule_key,
        "prod_sqlite_backup",
        "admin_system",
        "daily",
        "19:00",
        1,
        "never",
        nil,
        nil,
        0,
        nil,
        next_run_at,
        1,
        timestamp,
        timestamp
      ]
    )

    :ok
  end

  defp verify! do
    %{rows: [[@version]]} =
      SqliteRepo.query!("SELECT version FROM schema_migrations WHERE version = ?", [@version])

    %{rows: objects} =
      SqliteRepo.query!(
        "SELECT name FROM sqlite_master WHERE name IN (#{placeholders(@required_objects)}) ORDER BY name",
        @required_objects
      )

    if Enum.map(objects, &hd/1) |> Enum.sort() != Enum.sort(@required_objects) do
      raise "persistent schedules migration verification failed"
    end

    %{rows: [seed]} =
      SqliteRepo.query!(
        """
        SELECT handler_key, schedule_context, cadence, daily_at_utc, enabled,
               expiration_kind, expires_at, max_occurrences, revision
        FROM bnest_schedules WHERE schedule_key = ?
        """,
        [@schedule_key]
      )

    unless seed == [
             "prod_sqlite_backup",
             "admin_system",
             "daily",
             "19:00",
             1,
             "never",
             nil,
             nil,
             1
           ] do
      raise "persistent schedules seed policy is incompatible"
    end

    :ok
  end

  defp placeholders(values), do: Enum.map_join(values, ",", fn _value -> "?" end)
  defp migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
