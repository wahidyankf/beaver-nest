defmodule BnestApp.FamilyChatReleaseAndSlotsBindingTest do
  @moduledoc """
  Integration bindings for the family chat release-compatibility and independent-slot scenarios. Each test runs the
  scenario's steps through `BnestApp.Behaviour.IntegrationFamilyChatDriver` on a fresh test instance with the
  scenario's own signed-in identity, the same context the behaviour runner gives an integration scenario.
  """

  # The migrations and the slot listeners use the one application database and PubSub, so these run sequentially.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.IntegrationFamilyChatDriver, as: Driver
  alias BnestApp.FreshDatabaseCase
  alias BnestApp.TestInstance
  alias BnestAppWeb.ConnCase

  setup do
    assert TestInstance.state() == nil, "an earlier test left a test instance current"
    _spawned = FreshDatabaseCase.spawn_for!(%{}, FreshDatabaseCase.standard_accounts())
    on_exit(&FreshDatabaseCase.drop_current/0)

    scenario_key = "family-chat-release-and-slots"

    {conn, identity} =
      ConnCase.scenario_authenticated_conn(Phoenix.ConnTest.build_conn(), scenario_key)

    %{conn: conn, user_id: identity.user_id, test_identity: identity}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: An old release ignores the additive family chat schema
  test "an old release ignores the additive family chat schema", context do
    context =
      context
      |> Driver.prepare_behaviour(:migration_applied, [])
      |> Driver.perform_behaviour(:old_code_opens_database, [])

    assert Driver.behaviour_outcome?(context, :prior_release_unaffected, [])
    assert Driver.behaviour_outcome?(context, :no_prior_release_table_access, [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: An old release ignores the additive reply column
  test "an old release ignores the additive reply column", context do
    context =
      context
      |> Driver.prepare_behaviour(:reply_migration_applied, [])
      |> Driver.perform_behaviour(:pre_reply_release_opens_database, [])

    assert Driver.behaviour_outcome?(context, :pre_reply_columns_unchanged, [])
    assert Driver.behaviour_outcome?(context, :pre_reply_commits_have_no_target, [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Two independent slots do not exchange family chat PubSub events
  test "two independent slots do not exchange family chat PubSub events", context do
    context =
      context
      |> Driver.prepare_behaviour(:two_independent_slots, [])
      |> Driver.perform_behaviour(:message_commits_on_one_slot, [])

    assert Driver.behaviour_outcome?(context, :only_same_slot_sockets_receive, [])
    assert Driver.behaviour_outcome?(context, :other_slot_no_event, [])
  end
end
