defmodule BnestApp.Behaviour.IntegrationSupport do
  use ExBdd.Hooks

  alias BnestApp.Behaviour.TestIsolation.IntegrationAdapter

  # Existing scenarios still run on the shared base database (no spawn here until T9b). The
  # isolation adapter only installs the run secret and the wire state; it spawns nothing itself.
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

  # Drops whatever instance the scenario left current and clears the run secret.
  after_scenario context do
    IntegrationAdapter.release(context)
    context
  end
end
