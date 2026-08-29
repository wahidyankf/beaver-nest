defmodule BnestAppWeb.HealthControllerTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig
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

  test "readiness proves a reachable SQLite database once the phase switches to sqlite_primary" do
    runtime = TestRuntimeRoot.create!("health-sqlite")
    pointer_directory = Path.join(runtime.path, "pointer")
    File.mkdir_p!(pointer_directory)
    System.put_env("BNEST_STORAGE_CONFIG", Path.join(pointer_directory, "storage.json"))

    on_exit(fn ->
      StorageCoordinator.stop()
      System.delete_env("BNEST_STORAGE_CONFIG")
      TestRuntimeRoot.cleanup!(runtime)
    end)

    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    :ok = StorageCoordinator.ensure_started!(database_path)

    migrations_path = Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

    {:ok, _versions, _apps} =
      Ecto.Migrator.with_repo(SqliteRepo, &Ecto.Migrator.run(&1, migrations_path, :up, all: true))

    pointer = %{
      "schemaVersion" => 1,
      "databaseDirectory" => runtime.path,
      "databaseFilename" => "bnest.sqlite3",
      "phase" => "sqlite_primary",
      "migrationId" => "flat-files-v1-to-sqlite-v1"
    }

    File.write!(StorageConfig.pointer_path(), Jason.encode!(pointer))

    ready = get(build_conn(), "/health/ready")

    assert %{"status" => "ready", "sqliteReady" => true} = json_response(ready, 200)
  end
end
