defmodule BnestApp.FreshDatabaseCaseTest do
  # The case template every database-touching integration test will use (ADR 001, section 3). Its setup spawns
  # the test instance, and its teardown drops it. The seeded usernames carry the instance short id, so the
  # tests that seed pin the instance id with a tag.
  use BnestApp.FreshDatabaseCase, async: false

  @moduletag :test_instance

  alias BnestApp.FreshDatabaseCase
  alias BnestApp.SqliteRepo
  alias BnestApp.TestInstance

  test "a test starts on its own current instance, migrated and with no record", %{
    instance: instance
  } do
    assert TestInstance.state().instance_id == instance.instance_id
    assert instance.phase == :sqlite_primary

    assert %{rows: [[0]]} = SqliteRepo.query!("SELECT count(*) FROM bnest_records")
    assert %{rows: [[versions]]} = SqliteRepo.query!("SELECT count(*) FROM schema_migrations")
    assert versions > 0
  end

  test "a test with no seed has no account", %{accounts: accounts} do
    assert accounts == []
  end

  @tag phase: :flat_primary
  test "a phase tag selects the flat-primary phase", %{instance: instance} do
    assert instance.phase == :flat_primary
    assert File.dir?(instance.paths.flat_instance_root)
  end

  @tag instance_id: "f1e2d3c4b5a69788"
  @tag seed:
         {"fresh-case",
          %{
            "accounts" => [
              %{
                "username" => "test-user-f1e2d3c4-admin",
                "password" => "Synthetic!Pass1",
                "roles" => ["admin"]
              }
            ]
          }}
  test "a seed is applied after migration and its accounts are listed", %{
    accounts: accounts,
    instance: instance
  } do
    assert instance.instance_id == "f1e2d3c4b5a69788"
    assert accounts == ["test-user-f1e2d3c4-admin"]
  end

  test "a teardown that cannot validate the instance refuses, and the instance stays current", %{
    instance: instance
  } do
    marker = instance.paths.sqlite_marker_path
    original = File.read!(marker)
    File.write!(marker, "not a marker")

    try do
      error = assert_raise TestInstance.Error, fn -> FreshDatabaseCase.drop_current() end

      assert error.reason == :refused
      assert TestInstance.state().instance_id == instance.instance_id
    after
      File.write!(marker, original)
    end
  end
end
