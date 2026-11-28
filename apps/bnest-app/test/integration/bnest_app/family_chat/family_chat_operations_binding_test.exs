defmodule BnestApp.FamilyChatOperationsBindingTest do
  @moduledoc """
  Integration bindings for the family chat operations scenarios about system messages and push delivery retention.
  Each test runs the scenario's steps through `BnestApp.Behaviour.IntegrationFamilyChatDriver` on a fresh test
  instance, so the messages and delivery rows live in that instance's SQLite database.
  """

  # The instance and its database are shared by the test process, so these run sequentially.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.IntegrationFamilyChatDriver, as: Driver
  alias BnestApp.FreshDatabaseCase
  alias BnestApp.TestInstance

  setup do
    assert TestInstance.state() == nil, "an earlier test left a test instance current"
    _spawned = FreshDatabaseCase.spawn_for!(%{}, FreshDatabaseCase.standard_accounts())
    on_exit(&FreshDatabaseCase.drop_current/0)
    :ok
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A trusted producer posts an idempotent system message
  test "a trusted producer posts an idempotent system message" do
    context =
      %{}
      |> Driver.prepare_behaviour(:trusted_producer, [])
      |> Driver.perform_behaviour(:producer_posts_system_message, ["ruang-keluarga"])

    assert Driver.behaviour_outcome?(context, :system_message_committed, ["system"])

    context = Driver.perform_behaviour(context, :producer_retries_same_key, [])

    assert Driver.behaviour_outcome?(context, :system_message_unchanged, [])
    assert Driver.behaviour_outcome?(context, :exactly_one_system_message, [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Final delivery rows are soft-deleted after seven active days
  test "final delivery rows are soft-deleted after seven active days" do
    context =
      %{}
      |> Driver.prepare_behaviour(:final_rows_older_than_7_days, [])
      |> Driver.prepare_behaviour(:nonfinal_rows_same_age, [])
      |> Driver.perform_behaviour(:retention_job_runs, [])

    assert Driver.behaviour_outcome?(context, :completed_rows_soft_deleted, [])
    assert Driver.behaviour_outcome?(context, :nonfinal_rows_remain_active, [])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Soft-deleted delivery rows are purged after the grace period
  test "soft-deleted delivery rows are purged after the grace period" do
    context =
      %{}
      |> Driver.prepare_behaviour(:soft_deleted_rows_older_than_7_days, [])
      |> Driver.perform_behaviour(:retention_job_runs_again, [])

    assert Driver.behaviour_outcome?(context, :rows_purged, [])
    assert Driver.behaviour_outcome?(context, :retention_run_idempotent, [])
  end
end
