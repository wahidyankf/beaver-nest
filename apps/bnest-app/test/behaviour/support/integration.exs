defmodule BnestApp.Behaviour.IntegrationSupport do
  use ExBdd.Hooks

  import Phoenix.ConnTest, only: [build_conn: 0]

  alias BnestApp.Behaviour.TestIsolation.IntegrationAdapter
  alias BnestApp.FreshDatabaseCase
  alias BnestApp.TestInstance
  alias BnestAppWeb.ConnCase

  # An ExBdd scenario is one test (ADR 001, section 1), so every integration scenario runs on a fresh instance. The
  # before hook spawns it with the standard accounts and logs the scenario's identity in; the after hook drops it. The
  # scenario module runs under `BnestAppWeb.ScenarioCase`, which has no setup, so this hook is the only owner.
  #
  # Three kinds of scenario differ:
  #
  #   * `test_isolation.feature` and `test_instances.feature` spawn, end and check their instances through their
  #     adapter (`IntegrationAdapter.spawn_instance/2`, `establish_admin/1`). The generic hook spawns nothing, since a
  #     second spawn is refused.
  #   * a scenario tagged `@open-setup` needs an empty flat-primary instance with no seeded account, so `/setup` stays
  #     open. It spawns with no accounts and logs nobody in.
  #   * the `centralized_data.feature` scenarios import browser sources, which Bnest keeps as flat files in its
  #     records store, so they run on a flat-primary instance.
  #   * four `sqlite_storage.feature` scenarios hide or remove the instance's storage pointer and then log an
  #     administrator in. With no pointer, accounts are written to the flat records store, so that store has to be the
  #     instance's own: a flat-primary instance. On a SQLite-primary instance they land in the shared run base.
  @self_controlled_features ["test_isolation.feature", "test_instances.feature"]
  @flat_primary_features ["centralized_data.feature"]
  @flat_primary_scenarios [
    "Administrator optionally selects a valid custom database folder",
    "Private custom storage survives a sticky shared ancestor",
    "Unsafe database folder is rejected without mutation",
    "Invalid or changed source blocks cutover without data loss"
  ]

  before_scenario _context, name: "start with no test instance current" do
    case TestInstance.state() do
      nil -> :ok
      _leftover -> {:error, "an earlier scenario left a test instance current"}
    end
  end

  before_scenario context, name: "spawn a fresh test instance for the scenario" do
    {:ok, prepare(context)}
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

  defp prepare(context) do
    cond do
      self_controlled?(context) ->
        adapter_context(context)

      open_setup?(context) ->
        _spawned = FreshDatabaseCase.spawn_for!(Map.put(context, :phase, :flat_primary), [])
        adapter_context(context)

      true ->
        spawn_with_identity(context)
    end
  end

  # The scenario's own identity: the standard accounts are seeded into the instance, and this scenario's account is
  # seeded and logged in as a browser's login would. The driver reads `test_identity`, as it did under ConnCase.
  defp spawn_with_identity(context) do
    _spawned =
      FreshDatabaseCase.spawn_for!(
        Map.put(context, :phase, phase(context)),
        FreshDatabaseCase.standard_accounts()
      )

    scenario_key = "#{context.feature_file}:#{context.scenario_name}"
    {conn, identity} = ConnCase.scenario_authenticated_conn(build_conn(), scenario_key)

    Process.put(:bnest_behaviour_user_id, identity.user_id)

    context
    |> Map.put(:conn, conn)
    |> Map.put(:user_id, identity.user_id)
    |> Map.put(:test_identity, identity)
    |> adapter_context()
  end

  defp adapter_context(context) do
    context
    |> Map.put_new(:conn, build_conn())
    |> Map.put(:behaviour_driver, BnestApp.Behaviour.IntegrationHomePageDriver)
    |> IntegrationAdapter.prepare()
  end

  defp phase(context) do
    if context[:"flat-primary"] == true or flat_feature?(context) or
         context.scenario_name in @flat_primary_scenarios,
      do: :flat_primary,
      else: :sqlite_primary
  end

  defp self_controlled?(context), do: feature_in?(context, @self_controlled_features)
  defp flat_feature?(context), do: feature_in?(context, @flat_primary_features)
  defp open_setup?(context), do: context[:"open-setup"] == true

  defp feature_in?(context, features),
    do: Enum.any?(features, &String.ends_with?(context.feature_file, &1))
end
