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

  # The default destination is `<repository root>/data/backup`, and in the permanent checkout
  # the compiled root's is the production backup directory. Every test run therefore has its
  # own repository root, which the file store prefers over an inherited
  # `BNEST_REPOSITORY_ROOT` (`BnestApp.Backup.FileConfigStoreTest` proves the resolution).
  test "configures the test run's own backup repository root, never a checkout" do
    root = Application.get_env(:bnest_app, :backup_repository_root)

    assert is_binary(root)
    assert root =~ "/bnest/data/test/backup-repository/"
    refute String.starts_with?(__DIR__ <> "/", root <> "/")

    refute String.contains?(root, "/beaver-nest") and
             not String.contains?(root, "/bnest/data/test/")
  end
end
