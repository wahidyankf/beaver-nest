defmodule BnestApp.SqliteSchemaChecksumBindingTest do
  @moduledoc """
  Integration binding for the versioned SQLite migration scenario. The integration home driver opens an empty isolated
  database, applies the committed migration set twice against it, and compares the schema version, the indexes, and the
  migration records with the declared checksum.
  """

  # The migrations run against the one storage profile of the instance, so these run sequentially.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.IntegrationHomePageDriver, as: Driver
  alias BnestApp.FreshDatabaseCase
  alias BnestApp.TestInstance
  alias BnestAppWeb.ConnCase

  setup do
    assert TestInstance.state() == nil, "an earlier test left a test instance current"
    _spawned = FreshDatabaseCase.spawn_for!(%{}, FreshDatabaseCase.standard_accounts())
    on_exit(&FreshDatabaseCase.drop_current/0)

    {conn, identity} =
      ConnCase.scenario_authenticated_conn(
        Phoenix.ConnTest.build_conn(),
        "sqlite-schema-checksum"
      )

    %{conn: conn, user_id: identity.user_id, test_identity: identity}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Versioned SQLite migration creates the expected schema once
  test "versioned SQLite migration creates the expected schema once", context do
    context =
      context
      |> Driver.prepare_behaviour(:empty_isolated_database, [])
      |> Driver.perform_behaviour(:apply_migration_set_twice, [])

    assert Driver.behaviour_outcome?(context, :schema_matches_checksum, [])
    assert Driver.behaviour_outcome?(context, :no_duplicate_schema_objects, [])
  end
end
