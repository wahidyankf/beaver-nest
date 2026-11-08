defmodule BnestApp.TestInstance.DirectoriesTest do
  use ExUnit.Case, async: false

  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.TestInstance
  alias BnestApp.TestRuntimeRoot

  @instance_id "a1b2c3d4e5f6g7h8"
  @other_instance_id "z9y8x7w6v5u4t3s2"
  @run_marker ".bnest-test-run.json"
  @marker_name ".bnest-test-instance.json"

  setup do
    runtime = TestRuntimeRoot.create!("test-instance-dirs")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    %{runtime: runtime}
  end

  describe "create_dirs/3" do
    test "writes the instance marker before any database file exists", %{runtime: runtime} do
      assert {:ok, instance} = TestInstance.create_dirs(runtime, @instance_id, :sqlite_primary)
      paths = instance.paths

      assert instance.run_id == runtime.run_id
      assert instance.instance_id == @instance_id
      assert instance.phase == :sqlite_primary

      assert File.dir?(paths.db_directory)
      assert File.dir?(paths.backup_repository_directory)
      refute File.exists?(paths.db_file)

      assert %{
               "schemaVersion" => 1,
               "recordType" => "bnest-test-instance",
               "runId" => run_id,
               "instanceId" => @instance_id,
               "owner" => "bnest-test-harness",
               "createdAt" => created_at
             } = read_marker(paths.sqlite_marker_path)

      assert run_id == runtime.run_id
      assert {:ok, _timestamp, 0} = DateTime.from_iso8601(created_at)

      assert :ok = TestInstance.drop_dirs(instance)
    end

    test "creates a flat instance root only for the flat primary phase", %{runtime: runtime} do
      assert {:ok, sqlite_only} = TestInstance.create_dirs(runtime, @instance_id, :sqlite_primary)
      refute File.exists?(sqlite_only.paths.flat_instance_root)
      assert :ok = TestInstance.drop_dirs(sqlite_only)

      assert {:ok, flat} = TestInstance.create_dirs(runtime, @instance_id, :flat_primary)
      assert File.dir?(flat.paths.flat_instance_root)

      assert %{"recordType" => "bnest-test-instance", "instanceId" => @instance_id} =
               read_marker(flat.paths.flat_marker_path)

      assert :ok = TestInstance.drop_dirs(flat)
    end

    # A secondary BEAM boots on the flat instance root, and the application start validates a test root
    # with FileRecordBackend.new!/1, which reads a run marker named after the root's own basename.
    test "gives a flat instance root the run marker the application boot validates", %{
      runtime: runtime
    } do
      assert {:ok, flat} = TestInstance.create_dirs(runtime, @instance_id, :flat_primary)
      root = flat.paths.flat_instance_root

      assert %{backend: FileRecordBackend, root: ^root} = FileRecordBackend.new!(root)

      assert %{
               "recordType" => "bnest-test-run",
               "runId" => @instance_id,
               "owner" => "bnest-test-harness"
             } =
               read_marker(Path.join(root, @run_marker))

      assert :ok = TestInstance.drop_dirs(flat)
      refute File.exists?(root)
    end

    test "refuses an instance id that is not a safe identifier and creates nothing",
         %{runtime: runtime} do
      for bad <- ["../escape", "/tmp/escape", "SHORT"] do
        assert {:error, :invalid_instance_id} =
                 TestInstance.create_dirs(runtime, bad, :sqlite_primary)
      end

      refute File.exists?(Path.join(runtime.sqlite_path, "instances"))
      refute File.exists?(Path.join(runtime.path, "instances"))
    end

    test "refuses a run root that no longer exists", %{runtime: runtime} do
      missing = TestRuntimeRoot.create!("test-instance-missing")
      TestRuntimeRoot.cleanup!(missing)

      assert {:error, :run_root_missing} =
               TestInstance.create_dirs(missing, @instance_id, :sqlite_primary)

      refute File.exists?(missing.sqlite_path)
      assert File.exists?(runtime.sqlite_path)
    end

    test "refuses a run root whose marker is missing and writes nothing", %{runtime: runtime} do
      marker_path = Path.join(runtime.sqlite_path, @run_marker)
      bytes = File.read!(marker_path)
      File.rm!(marker_path)

      try do
        assert {:error, :invalid_marker} =
                 TestInstance.create_dirs(runtime, @instance_id, :sqlite_primary)

        refute File.exists?(Path.join(runtime.sqlite_path, "instances"))
      after
        File.write!(marker_path, bytes)
      end
    end

    test "refuses to create over an existing instance and leaves it untouched",
         %{runtime: runtime} do
      instance = create_instance!(runtime)

      assert {:error, :instance_exists} =
               TestInstance.create_dirs(runtime, @instance_id, :sqlite_primary)

      assert File.regular?(instance.paths.sqlite_marker_path)
      assert :ok = TestInstance.drop_dirs(instance)
    end
  end

  describe "create then drop" do
    test "leaves nothing of the instance behind, in either phase", %{runtime: runtime} do
      before_sqlite = runtime.sqlite_path |> File.ls!() |> Enum.sort()
      before_flat = runtime.path |> File.ls!() |> Enum.sort()

      for phase <- [:sqlite_primary, :flat_primary] do
        assert {:ok, instance} = TestInstance.create_dirs(runtime, @instance_id, phase)
        assert :ok = TestInstance.drop_dirs(instance)

        refute File.exists?(instance.paths.sqlite_instance_root)
        refute File.exists?(instance.paths.flat_instance_root)
      end

      assert runtime.sqlite_path |> File.ls!() |> Enum.sort() == before_sqlite
      assert runtime.path |> File.ls!() |> Enum.sort() == before_flat
      assert {:ok, _marker} = TestRuntimeRoot.validate(runtime.path)
      assert {:ok, _marker} = TestRuntimeRoot.validate_sqlite(runtime.sqlite_path)
    end
  end

  describe "drop_dirs/1 refusals" do
    test "refuses an unmarked directory and keeps it", %{runtime: runtime} do
      instance = create_instance!(runtime)
      File.rm!(instance.paths.sqlite_marker_path)

      assert {:error, {:refused, :unmarked}} = TestInstance.drop_dirs(instance)
      assert File.dir?(instance.paths.sqlite_instance_root)
    end

    test "refuses a marker that names another run or another instance", %{runtime: runtime} do
      for {key, value} <- [{"runId", "other-run-1"}, {"instanceId", @other_instance_id}] do
        instance = create_instance!(runtime)

        marker = instance.paths.sqlite_marker_path |> read_marker() |> Map.put(key, value)
        File.write!(instance.paths.sqlite_marker_path, Jason.encode!(marker))

        assert {:error, {:refused, :invalid_marker}} = TestInstance.drop_dirs(instance)
        assert File.dir?(instance.paths.sqlite_instance_root)

        File.rm_rf!(instance.paths.sqlite_instance_root)
      end
    end

    test "refuses an instance that holds a symlink and removes neither side",
         %{runtime: runtime} do
      instance = create_instance!(runtime)
      :ok = File.ln_s(runtime.path, Path.join(instance.paths.db_directory, "escape"))

      assert {:error, {:refused, :symlink}} = TestInstance.drop_dirs(instance)
      assert File.dir?(instance.paths.sqlite_instance_root)
      assert File.dir?(Path.join(runtime.path, "general"))
      assert File.regular?(Path.join(runtime.path, @run_marker))
    end

    test "refuses an instance root that is itself a symlink", %{runtime: runtime} do
      instance = create_instance!(runtime)
      real = Path.join(runtime.sqlite_path, "relocated-instance")
      File.rename!(instance.paths.sqlite_instance_root, real)
      :ok = File.ln_s(real, instance.paths.sqlite_instance_root)

      assert {:error, {:refused, :symlink}} = TestInstance.drop_dirs(instance)
      assert File.dir?(real)
      assert File.regular?(Path.join(real, @marker_name))

      File.rm!(instance.paths.sqlite_instance_root)
      File.rm_rf!(real)
    end

    test "refuses an instances directory that is a symlink into another place", %{
      runtime: runtime
    } do
      instance = create_instance!(runtime)
      instances = Path.join(runtime.sqlite_path, "instances")
      relocated = Path.join(runtime.sqlite_path, "relocated-instances")
      File.rename!(instances, relocated)
      :ok = File.ln_s(relocated, instances)

      assert {:error, {:refused, :symlink}} = TestInstance.drop_dirs(instance)
      assert File.regular?(Path.join([relocated, @instance_id, @marker_name]))

      File.rm!(instances)
      File.rm_rf!(relocated)
    end

    test "refuses an instance directory that lies outside the run root", %{runtime: runtime} do
      other = TestRuntimeRoot.create!("test-instance-other")
      on_exit(fn -> TestRuntimeRoot.cleanup!(other) end)
      outside = create_instance!(other)
      instance = create_instance!(runtime)

      moved_out =
        put_in(instance, [:paths, :sqlite_instance_root], outside.paths.sqlite_instance_root)

      assert {:error, {:refused, :outside_run}} = TestInstance.drop_dirs(moved_out)
      assert File.dir?(outside.paths.sqlite_instance_root)

      assert :ok = TestInstance.drop_dirs(outside)
      assert :ok = TestInstance.drop_dirs(instance)
    end

    test "refuses a struct whose paths do not follow from its instance id", %{runtime: runtime} do
      instance = create_instance!(runtime)
      forged = %{instance | instance_id: @other_instance_id}

      assert {:error, {:refused, :path_mismatch}} = TestInstance.drop_dirs(forged)
      assert File.dir?(instance.paths.sqlite_instance_root)

      assert :ok = TestInstance.drop_dirs(instance)
    end
  end

  describe "drop_dirs/1 refusals on the flat primary root" do
    test "refuses a flat primary instance whose flat marker is missing, and keeps both roots", %{
      runtime: runtime
    } do
      instance = create_flat_instance!(runtime)
      marker_path = instance.paths.flat_marker_path
      marker = File.read!(marker_path)
      File.rm!(marker_path)

      try do
        assert {:error, {:refused, :unmarked}} = TestInstance.drop_dirs(instance)
        assert File.dir?(instance.paths.flat_instance_root)
        assert File.dir?(instance.paths.sqlite_instance_root)
      after
        File.write!(marker_path, marker)
      end

      assert :ok = TestInstance.drop_dirs(instance)
    end

    test "refuses a flat primary instance whose flat root is a symlink, and removes neither side",
         %{runtime: runtime} do
      instance = create_flat_instance!(runtime)
      flat = instance.paths.flat_instance_root
      relocated = Path.join(runtime.path, "relocated-flat")
      File.rename!(flat, relocated)
      :ok = File.ln_s(relocated, flat)

      assert {:error, {:refused, :symlink}} = TestInstance.drop_dirs(instance)
      assert File.regular?(Path.join(relocated, @marker_name))
      assert File.dir?(instance.paths.sqlite_instance_root)

      File.rm!(flat)
      File.rm_rf!(relocated)
      File.rm_rf!(instance.paths.sqlite_instance_root)
    end

    test "refuses a flat primary instance that holds a symlink inside its flat root", %{
      runtime: runtime
    } do
      instance = create_flat_instance!(runtime)
      :ok = File.ln_s(runtime.path, Path.join(instance.paths.flat_instance_root, "escape"))

      assert {:error, {:refused, :symlink}} = TestInstance.drop_dirs(instance)
      assert File.dir?(instance.paths.flat_instance_root)
      assert File.regular?(Path.join(runtime.path, @run_marker))

      File.rm!(Path.join(instance.paths.flat_instance_root, "escape"))
      assert :ok = TestInstance.drop_dirs(instance)
    end

    test "refuses a flat root that appears under a sqlite primary instance", %{runtime: runtime} do
      assert {:ok, instance} = TestInstance.create_dirs(runtime, @instance_id, :sqlite_primary)
      File.mkdir_p!(Path.dirname(instance.paths.flat_instance_root))
      File.mkdir!(instance.paths.flat_instance_root)

      assert {:error, {:refused, :unexpected_flat_root}} = TestInstance.drop_dirs(instance)
      assert File.dir?(instance.paths.sqlite_instance_root)
      assert File.dir?(instance.paths.flat_instance_root)

      File.rmdir!(instance.paths.flat_instance_root)
      assert :ok = TestInstance.drop_dirs(instance)
    end
  end

  describe "drop_dirs/1 removal failure" do
    test "reports cleanup_failed with the retained path inside the run roots", %{runtime: runtime} do
      instance = create_instance!(runtime)
      root = instance.paths.sqlite_instance_root

      # Removing the `db` child needs write access to the instance root, so a read-only root
      # makes the removal fail while the markers still validate.
      File.chmod!(root, 0o500)

      try do
        assert {:error, {:cleanup_failed, _reason, ^root}} = TestInstance.drop_dirs(instance)
        assert String.starts_with?(root, runtime.sqlite_path <> "/")
        assert File.dir?(root)
      after
        File.chmod!(root, 0o700)
      end

      assert :ok = TestInstance.drop_dirs(instance)
    end
  end

  defp create_instance!(runtime) do
    assert {:ok, instance} = TestInstance.create_dirs(runtime, @instance_id, :sqlite_primary)
    instance
  end

  defp create_flat_instance!(runtime) do
    assert {:ok, instance} = TestInstance.create_dirs(runtime, @instance_id, :flat_primary)
    instance
  end

  defp read_marker(path), do: path |> File.read!() |> Jason.decode!()
end
