defmodule BnestApp.Behaviour.IntegrationSupport do
  use ExBdd.Hooks

  alias BnestApp.Behaviour.TestIsolation.IntegrationAdapter
  alias BnestApp.FreshDatabaseCase
  alias BnestApp.TestInstance

  # Fresh-database hooks (ADR 001, sections 1 and 3). They keep the boundary between scenarios clean and
  # spawn nothing themselves. A scenario that needs a test instance spawns it in its own Given, through its
  # adapter. Scenarios that still run on the shared base database (until T9b converts ConnCase) must keep it,
  # so a blanket spawn here would break them.
  before_scenario _context, name: "start with no test instance current" do
    case TestInstance.state() do
      nil -> :ok
      _leftover -> {:error, "an earlier scenario left a test instance current"}
    end
  end

  before_scenario context do
    BnestAppWeb.ConnCase.ensure_test_account!()
    scenario_key = "#{context.feature_file}:#{context.scenario_name}"

    {conn, identity} =
      BnestAppWeb.ConnCase.scenario_authenticated_conn(
        Phoenix.ConnTest.build_conn(),
        scenario_key
      )

    Process.put(:bnest_behaviour_user_id, identity.user_id)

    context
    |> Map.put(:conn, conn)
    |> Map.put(:user_id, identity.user_id)
    |> Map.put(:behaviour_driver, BnestApp.Behaviour.IntegrationHomePageDriver)
    |> IntegrationAdapter.prepare()
  end

  # Drops whatever instance the scenario left current, so the storage pointer returns to the run base. A drop
  # that cannot finish raises, which fails the scenario.
  after_scenario _context, name: "drop the test instance" do
    FreshDatabaseCase.drop_current()
    :ok
  end

  # Clears the wire state and the run secret.
  after_scenario context do
    IntegrationAdapter.release(context)
    context
  end
end
