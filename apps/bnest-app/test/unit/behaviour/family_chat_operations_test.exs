defmodule BnestApp.Behaviour.FamilyChatOperationsTest do
  @moduledoc """
  Unit bindings for the family chat operations scenarios about release compatibility and
  independent-slot PubSub. Each test runs the scenario's steps through the unit behaviour
  driver, which calls the production Family Chat code on the in-memory doubles.
  """

  # The stores are global to the VM, so these scenarios run sequentially.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.TestIsolation.UnitAdapter
  alias BnestApp.Behaviour.UnitFamilyChatDriver, as: FamilyChatDriver
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

  # The same isolation the behaviour runner gives each unit scenario, so this test starts from the state the scenario does.
  defp start(driver) do
    RoomStore.install(now: DateTime.utc_now())
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
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: An old release ignores the additive family chat schema
  test "an old release ignores the additive family chat schema" do
    context =
      start(FamilyChatDriver)
      |> FamilyChatDriver.prepare_behaviour(:migration_applied, [])
      |> FamilyChatDriver.perform_behaviour(:old_code_opens_database, [])

    assert FamilyChatDriver.behaviour_outcome?(context, :prior_release_unaffected, [])
    assert FamilyChatDriver.behaviour_outcome?(context, :no_prior_release_table_access, [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: An old release ignores the additive reply column
  test "an old release ignores the additive reply column" do
    context =
      start(FamilyChatDriver)
      |> FamilyChatDriver.prepare_behaviour(:reply_migration_applied, [])
      |> FamilyChatDriver.perform_behaviour(:pre_reply_release_opens_database, [])

    assert FamilyChatDriver.behaviour_outcome?(context, :pre_reply_columns_unchanged, [])
    assert FamilyChatDriver.behaviour_outcome?(context, :pre_reply_commits_have_no_target, [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Two independent slots do not exchange family chat PubSub events
  test "two independent slots do not exchange family chat PubSub events" do
    context =
      start(FamilyChatDriver)
      |> FamilyChatDriver.prepare_behaviour(:two_independent_slots, [])
      |> FamilyChatDriver.perform_behaviour(:message_commits_on_one_slot, [])

    assert FamilyChatDriver.behaviour_outcome?(context, :only_same_slot_sockets_receive, [])
    assert FamilyChatDriver.behaviour_outcome?(context, :other_slot_no_event, [])
  end
end
