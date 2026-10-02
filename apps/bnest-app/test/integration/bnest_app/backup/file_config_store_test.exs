defmodule BnestApp.Backup.FileConfigStoreTest do
  use ExUnit.Case, async: false

  alias BnestApp.Backup.Adapters.FileConfigStore

  # The real backup configuration names the production backup directory, so a test that runs
  # a backup without its own `BNEST_BACKUP_CONFIG` must resolve the test run's own path.
  test "resolves the test run's own configuration path, never the real one" do
    test_path = Application.fetch_env!(:bnest_app, :backup_config_path)
    previous = System.get_env("BNEST_BACKUP_CONFIG")
    System.delete_env("BNEST_BACKUP_CONFIG")

    on_exit(fn -> if previous, do: System.put_env("BNEST_BACKUP_CONFIG", previous) end)

    assert FileConfigStore.config_path() == test_path
    assert test_path =~ "/bnest/data/test/backup-config/"
    refute FileConfigStore.config_path() =~ "/.config/bnest/"
    assert FileConfigStore.config_path(FileConfigStore.new()) == test_path
  end

  test "an explicit BNEST_BACKUP_CONFIG wins over the test run's path" do
    previous = System.get_env("BNEST_BACKUP_CONFIG")
    explicit = Path.join(System.tmp_dir!(), "bnest-backup-config-test-user-explicit.json")
    System.put_env("BNEST_BACKUP_CONFIG", explicit)

    on_exit(fn ->
      if previous,
        do: System.put_env("BNEST_BACKUP_CONFIG", previous),
        else: System.delete_env("BNEST_BACKUP_CONFIG")
    end)

    assert FileConfigStore.config_path() == explicit
  end
end
