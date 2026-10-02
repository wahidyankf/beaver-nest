defmodule BnestAppWeb.HealthControllerTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.TestRuntimeRoot

  test "reports liveness, readiness, and the served release revision", %{conn: conn} do
    live = get(conn, "/health/live")

    assert %{"status" => "live", "revision" => revision} = json_response(live, 200)
    assert get_resp_header(live, "x-bnest-revision") == [revision]

    ready = get(build_conn(), "/health/ready")

    assert %{
             "status" => "ready",
             "revision" => ^revision,
             "sqliteReady" => false,
             "storageGeneration" => nil
           } =
             json_response(ready, 200)
  end

  test "reports the revision and slot the deployment names, on the body and the header" do
    put_environment("BNEST_RELEASE_REVISION", "test-user-revision")
    put_environment("BNEST_DEPLOY_SLOT", "blue")

    live = get(build_conn(), "/health/live")

    assert json_response(live, 200) == %{
             "status" => "live",
             "revision" => "test-user-revision",
             "slot" => "blue"
           }

    assert get_resp_header(live, "x-bnest-revision") == ["test-user-revision"]

    ready = get(build_conn(), "/health/ready")

    assert %{"status" => "ready", "revision" => "test-user-revision", "slot" => "blue"} =
             json_response(ready, 200)

    assert get_resp_header(ready, "x-bnest-revision") == ["test-user-revision"]
  end

  test "is live but answers not ready while the deployment's peer slot cannot be reached" do
    # This test node runs without distribution, so no peer can answer its ping.
    put_environment("BNEST_DEPLOY_PEER", "test-user-peer@test-user-host")

    assert %{"status" => "live"} = json_response(get(build_conn(), "/health/live"), 200)

    ready = get(build_conn(), "/health/ready")

    assert json_response(ready, 503) == %{"status" => "not_ready"}
    assert [_revision] = get_resp_header(ready, "x-bnest-revision")
  end

  test "readiness proves a reachable SQLite database once the phase switches to sqlite_primary" do
    runtime = TestRuntimeRoot.create!("health-sqlite")
    pointer_directory = Path.join(runtime.path, "pointer")
    File.mkdir_p!(pointer_directory)
    System.put_env("BNEST_STORAGE_CONFIG", Path.join(pointer_directory, "storage.json"))

    on_exit(fn ->
      SqliteCoordinator.stop()
      System.delete_env("BNEST_STORAGE_CONFIG")
      TestRuntimeRoot.cleanup!(runtime)
    end)

    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    :ok = SqliteCoordinator.ensure_started!(database_path)

    :ok = PersistentSchedules.apply_and_verify!(DateTime.utc_now())

    pointer = %{
      "schemaVersion" => 1,
      "databaseDirectory" => runtime.sqlite_path,
      "databaseFilename" => "bnest.sqlite3",
      "phase" => "sqlite_primary",
      "migrationId" => "flat-files-v1-to-sqlite-v1"
    }

    File.write!(FileConfigStore.pointer_path(), Jason.encode!(pointer))

    ready = get(build_conn(), "/health/ready")

    assert %{"status" => "ready", "sqliteReady" => true} = json_response(ready, 200)
  end

  defp put_environment(name, value) do
    previous = System.get_env(name)
    System.put_env(name, value)

    on_exit(fn ->
      if previous, do: System.put_env(name, previous), else: System.delete_env(name)
    end)
  end
end
