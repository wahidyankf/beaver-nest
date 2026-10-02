defmodule BnestApp.Backup.ConfigTest do
  use ExUnit.Case, async: true

  alias BnestApp.Backup

  # The real backup configuration names the production backup directory, so a test that runs
  # a backup without its own `BNEST_BACKUP_CONFIG` must resolve the test run's own path. The
  # unit layer reads no configuration file at all: Backup's configuration store is in
  # memory. `BnestApp.Backup.FileConfigStoreTest` proves the file store's own resolution.
  test "resolves the test run's own configuration path, never the real one" do
    test_path = Application.fetch_env!(:bnest_app, :backup_config_path)

    assert test_path =~ "/bnest/data/test/backup-config/"
    refute test_path =~ "/.config/bnest/"
    assert Backup.adapter(:config_store) == BnestApp.Test.InMemory.BackupConfigStore
  end
end
