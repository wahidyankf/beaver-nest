defmodule BnestApp.Backup.ConfigTest do
  use ExUnit.Case, async: true

  alias BnestApp.Backup.Config

  # The real backup configuration names the production backup directory, so a test that runs
  # a backup without its own `BNEST_BACKUP_CONFIG` must resolve the test run's own path.
  test "resolves the test run's own configuration path, never the real one" do
    test_path = Application.fetch_env!(:bnest_app, :backup_config_path)

    assert Config.config_path() == test_path
    assert test_path =~ "/bnest/data/test/backup-config/"
    refute Config.config_path() =~ "/.config/bnest/"
  end
end
