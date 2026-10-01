defmodule BnestApp.Storage.ConfigTest do
  use ExUnit.Case, async: false

  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Domain.Location

  setup do
    run_id = "cfg-" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
    root = Path.join([System.tmp_dir!(), "bnest-storage-config-test", run_id])
    File.mkdir_p!(root)
    pointer = Path.join(root, "storage.json")
    previous = System.get_env("BNEST_STORAGE_CONFIG")
    System.put_env("BNEST_STORAGE_CONFIG", pointer)

    on_exit(fn ->
      if previous,
        do: System.put_env("BNEST_STORAGE_CONFIG", previous),
        else: System.delete_env("BNEST_STORAGE_CONFIG")

      File.rm_rf!(root)
    end)

    %{root: root, pointer: pointer}
  end

  describe "read/0" do
    test "reports absent when no pointer file exists" do
      assert FileConfigStore.read() == {:error, :absent}
    end

    test "reports invalid for malformed content", %{pointer: pointer} do
      File.write!(pointer, "not json")
      assert FileConfigStore.read() == {:error, :invalid}
    end

    test "reports invalid for well-formed JSON missing the required shape", %{pointer: pointer} do
      File.write!(pointer, Jason.encode!(%{"schemaVersion" => 1, "recordType" => "other"}))
      assert FileConfigStore.read() == {:error, :invalid}
    end
  end

  describe "pointer_path/0" do
    test "falls back to the default directory when BNEST_STORAGE_CONFIG is unset" do
      System.delete_env("BNEST_STORAGE_CONFIG")
      isolated = Application.get_env(:bnest_app, :storage_config_path)
      Application.delete_env(:bnest_app, :storage_config_path)
      on_exit(fn -> Application.put_env(:bnest_app, :storage_config_path, isolated) end)

      assert FileConfigStore.pointer_path() ==
               Path.join(Location.config_directory(), "storage.json")
    end
  end

  describe "phase/0" do
    test "reports flat_primary for a default pointer" do
      FileConfigStore.ensure_default!()
      assert FileConfigStore.phase() == :flat_primary
    end
  end

  describe "ensure_default!/0" do
    test "creates the default flat_primary pointer once", %{pointer: pointer} do
      config = FileConfigStore.ensure_default!()
      assert config["phase"] == "flat_primary"
      assert config["databaseDirectory"] == Storage.default_directory()
      assert config["databaseFilename"] == "bnest.sqlite3"
      assert {:ok, ^config} = FileConfigStore.read()
      stat = File.stat!(pointer)
      assert Bitwise.band(stat.mode, 0o777) == 0o600
    end

    test "is idempotent", %{} do
      first = FileConfigStore.ensure_default!()
      second = FileConfigStore.ensure_default!()
      assert first == second
    end
  end

  describe "persist_directory/1" do
    test "accepts a writable absolute directory and locks after creation", %{root: root} do
      custom = Path.join(root, "custom")
      File.mkdir_p!(custom)
      assert {:ok, config} = Storage.persist_directory(custom)
      assert config["databaseDirectory"] == custom
      assert Storage.persist_directory(Path.join(root, "other")) == {:error, :immutable}
    end

    test "accepts a private directory beneath a sticky world-writable parent", %{root: root} do
      shared = Path.join(root, "shared")
      custom = Path.join(shared, "private")
      File.mkdir_p!(custom)
      {_output, 0} = System.cmd("chmod", ["1777", shared])
      File.chmod!(custom, 0o700)

      assert {:ok, config} = Storage.persist_directory(custom)
      assert config["databaseDirectory"] == custom
    end

    test "rejects an existing world-writable directory", %{root: root} do
      custom = Path.join(root, "world-writable")
      File.mkdir_p!(custom)
      File.chmod!(custom, 0o777)

      assert Storage.persist_directory(custom) == {:error, :world_writable}
      assert FileConfigStore.read() == {:error, :absent}
    end

    test "rejects a relative directory without mutation" do
      assert Storage.persist_directory("relative/path") == {:error, :not_absolute}
      assert FileConfigStore.read() == {:error, :absent}
    end

    test "rejects a non-binary directory without mutation" do
      assert Storage.persist_directory(nil) == {:error, :not_absolute}
      assert FileConfigStore.read() == {:error, :absent}
    end

    test "accepts a directory whose parent does not exist yet", %{root: root} do
      target = Path.join([root, "not-created-yet", "db"])
      assert {:ok, config} = Storage.persist_directory(target)
      assert config["databaseDirectory"] == target
    end

    test "rejects reuse of an existing invalid pointer without mutation", %{
      root: root,
      pointer: pointer
    } do
      File.write!(pointer, "not json")
      custom = Path.join(root, "custom-over-invalid")
      File.mkdir_p!(custom)
      assert Storage.persist_directory(custom) == {:error, :invalid}
    end

    test "rejects a symlinked directory without mutation", %{root: root} do
      target = Path.join(root, "real")
      link = Path.join(root, "link")
      File.mkdir_p!(target)
      File.ln_s!(target, link)
      assert Storage.persist_directory(link) == {:error, :symlink}
      assert FileConfigStore.read() == {:error, :absent}
    end

    test "rejects a directory inside the repository" do
      repository_root = Path.expand("../../../../..", __DIR__)
      assert Storage.persist_directory(repository_root) == {:error, :unsafe_location}
      assert FileConfigStore.read() == {:error, :absent}
    end

    test "rejects a world-writable parent directory", %{root: root} do
      parent = Path.join(root, "shared")
      File.mkdir_p!(parent)
      File.chmod!(parent, 0o777)
      target = Path.join(parent, "db")
      assert Storage.persist_directory(target) == {:error, :world_writable}
      assert FileConfigStore.read() == {:error, :absent}
    end
  end

  describe "activate_sqlite_primary!/0" do
    test "flips only the phase field" do
      FileConfigStore.ensure_default!()
      updated = FileConfigStore.activate_sqlite_primary!()
      assert updated["phase"] == "sqlite_primary"
      assert FileConfigStore.phase() == :sqlite_primary
    end
  end

  describe "resolved_database_path/0" do
    test "falls back to the default path when unconfigured" do
      assert FileConfigStore.resolved_database_path() ==
               Path.join(Storage.default_directory(), "bnest.sqlite3")
    end

    test "uses the persisted custom location", %{root: root} do
      custom = Path.join(root, "custom2")
      File.mkdir_p!(custom)
      {:ok, _config} = Storage.persist_directory(custom)
      assert FileConfigStore.resolved_database_path() == Path.join(custom, "bnest.sqlite3")
    end
  end
end
