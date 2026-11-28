defmodule BnestApp.SharedSchedulerBindingTest do
  @moduledoc """
  Integration binding for the scheduled backup scenario that a second family handler shares the one scheduler. It runs
  the scenario's steps through `BnestApp.Behaviour.IntegrationHomePageDriver` on a fresh test instance, so the schedule,
  the coordinator's claim and the verified runs all go through the instance's SQLite database.
  """

  # The instance and its scheduler store are shared by the test process, so this runs alone.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.IntegrationHomePageDriver, as: Driver
  alias BnestApp.FreshDatabaseCase
  alias BnestApp.TestInstance

  setup do
    assert TestInstance.state() == nil, "an earlier test left a test instance current"
    _spawned = FreshDatabaseCase.spawn_for!(%{}, FreshDatabaseCase.standard_accounts())
    on_exit(&FreshDatabaseCase.drop_current/0)
    :ok
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: Reuse one scheduler across contexts
  test "reuse one scheduler across contexts" do
    context =
      %{}
      |> Driver.prepare_behaviour(:second_family_handler, [])
      |> Driver.perform_behaviour(:run_second_handler, [])

    assert Driver.behaviour_outcome?(context, :shared_execution, [])
    assert Driver.behaviour_outcome?(context, :shared_ledger_and_inventory, [])
  end
end
