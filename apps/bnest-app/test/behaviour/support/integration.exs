defmodule BnestApp.Behaviour.IntegrationSupport do
  use ExBdd.Hooks

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
  end
end
