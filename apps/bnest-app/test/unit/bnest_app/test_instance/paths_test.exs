defmodule BnestApp.TestInstance.PathsTest do
  use ExUnit.Case, async: true

  alias BnestApp.TestInstance.Paths

  @run "unit-run-1"
  @flat "/synthetic/data/test/runs/unit-run-1"
  @sqlite "/synthetic/bnest/data/test/runs/unit-run-1"
  @instance "a1b2c3d4e5f6g7h8"

  test "derives every instance path from the two run roots and the instance id" do
    assert {:ok, paths} = Paths.derive(@flat, @sqlite, @run, @instance)

    assert paths.run_id == @run
    assert paths.instance_id == @instance
    assert paths.short_id == "a1b2c3d4"
    assert paths.generation == "test-a1b2c3d4e5f6g7h8"

    assert paths.flat_run_root == @flat
    assert paths.sqlite_run_root == @sqlite
    assert paths.flat_instance_root == "#{@flat}/instances/#{@instance}"
    assert paths.sqlite_instance_root == "#{@sqlite}/instances/#{@instance}"
    assert paths.flat_marker_path == "#{@flat}/instances/#{@instance}/.bnest-test-instance.json"

    assert paths.sqlite_marker_path ==
             "#{@sqlite}/instances/#{@instance}/.bnest-test-instance.json"

    assert paths.db_directory == "#{@sqlite}/instances/#{@instance}/db"
    assert paths.db_file == "#{@sqlite}/instances/#{@instance}/db/bnest.sqlite3"

    assert paths.backup_repository_directory ==
             "#{@sqlite}/instances/#{@instance}/backup-repository"

    assert paths.storage_config_directory == "#{@sqlite}/storage-config"
    assert paths.storage_pointer_path == "#{@sqlite}/storage-config/storage.json"
    assert paths.backup_config_path == "#{@sqlite}/storage-config/backup.json"
  end

  test "keeps the database and backup repository beside each other, never one inside the other" do
    assert {:ok, paths} = Paths.derive(@flat, @sqlite, @run, @instance)

    refute String.starts_with?(paths.backup_repository_directory, paths.db_directory <> "/")
    refute String.starts_with?(paths.db_directory, paths.backup_repository_directory <> "/")
  end

  test "rejects an instance id that is not exactly sixteen lowercase letters or digits" do
    bad_ids = [
      "",
      "short",
      "a1b2c3d4e5f6g7h",
      "a1b2c3d4e5f6g7h8a",
      "A1B2C3D4E5F6G7H8",
      "a1b2c3d4e5f6g7h-",
      "a1b2c3d4e5f6g7h8\n",
      "../../etc/passwd",
      "/synthetic/abs/x",
      nil
    ]

    for bad <- bad_ids do
      assert Paths.derive(@flat, @sqlite, @run, bad) == {:error, :invalid_instance_id}
    end
  end

  test "rejects a run id that is empty, traverses, is absolute or is not a slug" do
    bad_runs = ["", "../unit", "unit/../../x", "/abs/run", "UPPER", "-leading", nil]

    for bad <- bad_runs do
      assert Paths.derive(@flat, @sqlite, bad, @instance) == {:error, :invalid_run_id}
    end
  end

  test "rejects roots that are relative, traverse, are not normalised or do not end in the run id" do
    assert Paths.derive("relative/runs/#{@run}", @sqlite, @run, @instance) ==
             {:error, :invalid_root}

    assert Paths.derive(@flat <> "/..", @sqlite, @run, @instance) == {:error, :invalid_root}
    assert Paths.derive(@flat <> "/", @sqlite, @run, @instance) == {:error, :invalid_root}

    assert Paths.derive(@flat, @sqlite <> "/x/../" <> @run, @run, @instance) ==
             {:error, :invalid_root}

    assert Paths.derive("/synthetic/data/test/runs/other-run", @sqlite, @run, @instance) ==
             {:error, :invalid_root}

    assert Paths.derive(nil, @sqlite, @run, @instance) == {:error, :invalid_root}
    assert Paths.derive(@flat, "/", @run, @instance) == {:error, :invalid_root}
  end

  test "the storage pointer names the instance database and its generation" do
    assert {:ok, paths} = Paths.derive(@flat, @sqlite, @run, @instance)

    assert Paths.storage_pointer(paths) == %{
             "schemaVersion" => 1,
             "databaseDirectory" => "#{@sqlite}/instances/#{@instance}/db",
             "databaseFilename" => "bnest.sqlite3",
             "phase" => "flat_primary",
             "migrationId" => "flat-files-v1-to-sqlite-v1",
             "databaseGeneration" => "test-#{@instance}"
           }
  end

  test "an invalid run id is reported before any root or instance id" do
    assert Paths.derive("relative", "relative", "../bad", "short") == {:error, :invalid_run_id}
  end
end
