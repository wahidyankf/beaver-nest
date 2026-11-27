defmodule BnestApp.Behaviour.SqliteStorageMigrationTest do
  @moduledoc """
  Unit binding for the versioned SQLite migration scenario. The unit behaviour driver applies the committed migration
  set twice on its in-memory ledger and compares the schema and the migration records with the declared checksum.
  """

  # The stores are global to the VM, so this scenario runs alone.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.TestIsolation.UnitAdapter
  alias BnestApp.Behaviour.UnitHomePageDriver
  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore
  alias BnestApp.Test.InMemory.CapacityProbe
  alias BnestApp.Test.InMemory.DatabaseSnapshot
  alias BnestApp.Test.InMemory.IgnoreCheck
  alias BnestApp.Test.InMemory.MessagePublisher
  alias BnestApp.Test.InMemory.PushSender
  alias BnestApp.Test.InMemory.ReleaseEnvironment
  alias BnestApp.Test.InMemory.RoomStore
  alias BnestApp.Test.InMemory.ScheduleStore

  # The unit layer's fixed clock. The scenario runs from it, so the test never reads the system clock.
  @now ~U[2026-09-18 20:00:00Z]

  # The same isolation the behaviour runner gives each unit scenario, so this test starts from the state the
  # scenario does.
  defp start(driver, now) do
    RoomStore.install(now: now)
    ScheduleStore.install()
    BackupConfigStore.install()
    ArtifactStore.install()
    DatabaseSnapshot.install()
    CapacityProbe.install()
    IgnoreCheck.install()
    ReleaseEnvironment.install()
    :ok = MessagePublisher.forget_published()
    :ok = PushSender.forget_sent()

    %{behaviour_driver: driver} |> UnitAdapter.prepare()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Versioned SQLite migration creates the expected schema once
  test "versioned SQLite migration creates the expected schema once" do
    context =
      start(UnitHomePageDriver, @now)
      |> UnitHomePageDriver.prepare_behaviour(:empty_isolated_database, [])
      |> UnitHomePageDriver.perform_behaviour(:apply_migration_set_twice, [])

    assert UnitHomePageDriver.behaviour_outcome?(context, :schema_matches_checksum, [])
    assert UnitHomePageDriver.behaviour_outcome?(context, :no_duplicate_schema_objects, [])
  end
end
