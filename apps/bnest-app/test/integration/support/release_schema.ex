defmodule BnestApp.Test.ReleaseSchema do
  @moduledoc """
  The release side of the schema-parity check (ADR 001, section 4), shared by the parity test and the
  `test_isolation.feature` schema scenario.

  `with_release_build/2` builds an empty database with the release migration entry points, in the order
  `tools/deployment.mjs` runs them, and calls the function while that database is the current one. The
  database lives in a scratch instance directory under the run roots, and it is removed afterwards. Only
  the storage pointer is switched, so the entry points open the file through the same `SqliteRepo` the
  app uses.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Release.Migrations.FamilyChat, as: ReleaseFamilyChat
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.SqliteRepo
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Fingerprint
  alias BnestApp.TestInstance.Switch

  @doc "The schema fingerprint, applied versions, release schedule keys and rooms of the current database."
  def observe do
    %{
      fingerprint: Fingerprint.current(),
      versions: applied_versions(),
      schedule_keys: schedule_keys(),
      rooms: rooms()
    }
  end

  @doc "The migration versions the current database has applied, in order."
  def applied_versions do
    %{rows: rows} = SqliteRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    Enum.map(rows, fn [version] -> version end)
  end

  @doc """
  Builds the release database, calls `fun` while it is current, then restores the state the call found
  and removes the scratch directory. No other database may be current when this is called.
  """
  def with_release_build(run, fun) do
    original = Switch.snapshot()
    {:ok, scratch} = TestInstance.create_dirs(run, random_instance_id(), :sqlite_primary)

    try do
      :ok = Switch.activate!(scratch)
      :ok = PersistentSchedules.apply_and_verify!(DateTime.utc_now())
      :ok = ReleaseFamilyChat.apply_and_verify!()
      fun.()
    after
      :ok = Switch.restore!(original, scratch.paths)
      :ok = TestInstance.drop_dirs(scratch)
    end
  end

  defp schedule_keys do
    %{rows: rows} =
      SqliteRepo.query!("SELECT schedule_key FROM bnest_schedules ORDER BY schedule_key")

    Enum.map(rows, fn [key] -> key end)
  end

  defp rooms do
    %{rows: rows} = SqliteRepo.query!("SELECT slug, name FROM family_chat_rooms ORDER BY slug")
    rows
  end

  defp random_instance_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
