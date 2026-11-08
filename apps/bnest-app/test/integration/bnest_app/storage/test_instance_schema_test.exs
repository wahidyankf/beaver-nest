defmodule BnestApp.Storage.TestInstanceSchemaTest do
  # ADR 001 section 4, "Schema parity check": a spawned test instance must have the schema the
  # release migrations produce, and the release seeds and nothing else.
  #
  # The release side runs in this file, not in test/support, because it needs the scratch instance
  # plumbing and the release entry points. The source scan only covers test/support, so the DDL in
  # the negative cases lives here too; those cases run on a throwaway instance that is dropped at once.
  use ExUnit.Case, async: false

  @moduletag :test_instance

  alias BnestApp.SqliteRepo
  alias BnestApp.Test.MigrationFiles
  alias BnestApp.Test.ReleaseSchema
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Fingerprint

  @release_schedule_keys ["family-chat-push-retention-daily", "prod-sqlite-backup-daily"]
  @release_room [["ruang-keluarga", "Ruang Keluarga"]]

  setup do
    run = TestInstance.application_run!()
    assert TestInstance.state() == nil

    on_exit(fn ->
      case TestInstance.state() do
        nil -> :ok
        instance -> TestInstance.drop!(instance)
      end
    end)

    %{run: run}
  end

  test "a spawned instance has the same fingerprint as a database built by the release entry points",
       %{run: run} do
    spawned = spawned_observation(run)
    release = with_release_build(run, &observe/0)

    assert spawned.fingerprint == release.fingerprint
  end

  test "both databases hold exactly the migration versions in the migrations directory", %{
    run: run
  } do
    expected = MigrationFiles.versions()
    assert expected != []

    assert spawned_observation(run).versions == expected
    assert with_release_build(run, &observe/0).versions == expected
  end

  test "both databases hold the release seeds and no other schedule", %{run: run} do
    for observed <- [spawned_observation(run), with_release_build(run, &observe/0)] do
      assert observed.schedule_keys == @release_schedule_keys
      assert observed.rooms == @release_room
    end
  end

  test "the fingerprint changes when an extra object exists", %{run: run} do
    instance = TestInstance.spawn!(run)
    before = Fingerprint.current()

    SqliteRepo.query!("CREATE INDEX test_extra_index ON bnest_schedules (schedule_key)")

    refute Fingerprint.current() == before
    assert :ok = TestInstance.drop!(instance)
  end

  test "the fingerprint changes when a migration version is missing", %{run: run} do
    instance = TestInstance.spawn!(run)
    before = Fingerprint.current()
    [latest | _older] = Enum.reverse(MigrationFiles.versions())

    SqliteRepo.query!("DELETE FROM schema_migrations WHERE version = ?", [latest])

    refute Fingerprint.current() == before
    assert :ok = TestInstance.drop!(instance)
  end

  # The spawned instance is measured and dropped before the release build, so only one database
  # is current at a time, as in every other test.
  defp spawned_observation(run) do
    instance = TestInstance.spawn!(run)
    observed = observe()
    assert :ok = TestInstance.drop!(instance)
    observed
  end

  # The release side and its observation are shared with the test_isolation schema scenario
  # (`BnestApp.Test.ReleaseSchema`), so both measure the same release database.
  defp with_release_build(run, fun), do: ReleaseSchema.with_release_build(run, fun)

  defp observe, do: ReleaseSchema.observe()
end
