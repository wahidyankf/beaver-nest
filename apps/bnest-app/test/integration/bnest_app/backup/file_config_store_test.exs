defmodule BnestApp.Backup.FileConfigStoreTest do
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.FileConfigStore

  # The checkout this test was compiled in: in the permanent checkout its `data/backup` is the
  # production backup directory.
  @checkout Path.expand("../../../../../..", __DIR__)

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

  # The default destination is `<repository root>/data/backup`. A test inheriting the
  # deployment's `BNEST_REPOSITORY_ROOT`, or built in the permanent checkout, must still
  # resolve its own run's root, never a checkout.
  test "resolves the test run's own repository root, never a checkout" do
    restore = put_repository_root_env(nil)
    on_exit(restore)

    root = FileConfigStore.repository_root()

    assert root =~ "/bnest/data/test/backup-repository/"
    refute root == @checkout
    refute String.starts_with?(@checkout <> "/", root <> "/")

    refute String.contains?(root, "/beaver-nest") and
             not String.contains?(root, "/bnest/data/test/")

    assert FileConfigStore.repository_root(FileConfigStore.new()) == root
  end

  test "an inherited BNEST_REPOSITORY_ROOT naming the checkout never wins in a test" do
    restore = put_repository_root_env(@checkout)
    on_exit(restore)

    assert FileConfigStore.repository_root() ==
             Application.get_env(:bnest_app, :backup_repository_root)

    refute FileConfigStore.repository_root() == @checkout
  end

  # The test run's root is no git repository, so nothing marks its `data/backup` ignored and
  # a backup into the unconfigured default is refused before any directory is created.
  test "the unconfigured default destination fails closed" do
    restore = put_repository_root_env(@checkout)
    on_exit(restore)
    use_absent_backup_config!()

    default = Backup.default_directory()

    assert Backup.destination() == {:error, :default_not_ignored}
    assert Backup.run() == {:error, :default_not_ignored}
    refute File.exists?(default)
    refute String.starts_with?(default, @checkout <> "/")
  end

  # With nothing saved, a backup goes to the default destination, which is the run's own root's
  # `data/backup` even when the deployment's variable names the checkout. Resolving it is
  # refused and leaves that root as it was, so the checkout's `data/backup` is never named,
  # listed or written. The assertions about where the default lies come before any resolution:
  # a run without its own root would resolve the checkout here.
  test "the test run's default destination lies in its own root and resolving it creates nothing" do
    on_exit(put_repository_root_env(@checkout))
    use_absent_backup_config!()

    root = Application.get_env(:bnest_app, :backup_repository_root)
    assert is_binary(root)
    default = Backup.default_directory()

    assert default == Path.join(root, "data/backup")
    assert default =~ "/bnest/data/test/backup-repository/"
    refute default == Path.join(@checkout, "data/backup")
    refute String.starts_with?(default, @checkout <> "/")

    listing = tree(root)

    assert Backup.destination() == {:error, :default_not_ignored}
    assert Backup.read_destination() == {:error, :default_not_ignored}
    assert Backup.run() == {:error, :default_not_ignored}

    assert tree(root) == listing
    refute File.exists?(default)
  end

  # Production never configures `:backup_repository_root`: there the deployment's
  # `BNEST_REPOSITORY_ROOT` wins, else the compiled checkout.
  test "without the test setting, BNEST_REPOSITORY_ROOT and then the checkout resolve" do
    previous_setting = Application.fetch_env(:bnest_app, :backup_repository_root)
    Application.delete_env(:bnest_app, :backup_repository_root)
    explicit = Path.join(System.tmp_dir!(), "bnest-repository-test-user-explicit")
    restore = put_repository_root_env(explicit)

    on_exit(fn ->
      restore.()

      with {:ok, setting} <- previous_setting,
           do: Application.put_env(:bnest_app, :backup_repository_root, setting)
    end)

    assert FileConfigStore.repository_root() == explicit
    System.delete_env("BNEST_REPOSITORY_ROOT")
    assert FileConfigStore.repository_root() == @checkout
  end

  # Points the backup configuration at a file nothing writes, so no destination is saved, and
  # restores `BNEST_BACKUP_CONFIG` when the test exits.
  defp use_absent_backup_config! do
    previous = System.get_env("BNEST_BACKUP_CONFIG")

    absent =
      Path.join(
        System.tmp_dir!(),
        "bnest-backup-config-test-user-absent-#{System.unique_integer([:positive])}.json"
      )

    System.put_env("BNEST_BACKUP_CONFIG", absent)

    on_exit(fn ->
      if previous,
        do: System.put_env("BNEST_BACKUP_CONFIG", previous),
        else: System.delete_env("BNEST_BACKUP_CONFIG")
    end)
  end

  # Whether `root` exists and every entry beneath it.
  defp tree(root), do: {File.exists?(root), Path.wildcard(Path.join(root, "**"), match_dot: true)}

  # Sets (or, given nil, removes) `BNEST_REPOSITORY_ROOT` and returns the function restoring it.
  defp put_repository_root_env(value) do
    previous = System.get_env("BNEST_REPOSITORY_ROOT")

    if value,
      do: System.put_env("BNEST_REPOSITORY_ROOT", value),
      else: System.delete_env("BNEST_REPOSITORY_ROOT")

    fn ->
      if previous,
        do: System.put_env("BNEST_REPOSITORY_ROOT", previous),
        else: System.delete_env("BNEST_REPOSITORY_ROOT")
    end
  end
end
