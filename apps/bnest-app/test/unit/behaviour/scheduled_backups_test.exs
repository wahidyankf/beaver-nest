defmodule BnestApp.Behaviour.ScheduledBackupsTest do
  @moduledoc """
  Unit bindings for the scheduled backup scenarios the home-page unit driver runs against the in-memory doubles,
  each test running the scenario's steps through that driver as the behaviour runner does.
  """

  # The stores are global to the VM, so these scenarios run sequentially.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.TestIsolation.UnitAdapter
  alias BnestApp.Behaviour.UnitHomePageDriver, as: HomePageDriver
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
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: Reuse one scheduler across contexts
  test "reuse one scheduler across contexts" do
    context =
      start(HomePageDriver, @now)
      |> HomePageDriver.prepare_behaviour(:second_family_handler, [])
      |> HomePageDriver.perform_behaviour(:run_second_handler, [])

    assert HomePageDriver.behaviour_outcome?(context, :shared_execution, [])
    assert HomePageDriver.behaviour_outcome?(context, :shared_ledger_and_inventory, [])
  end
end
