defmodule BnestApp.TestBackupDestination do
  @moduledoc """
  Test-only isolated backup destination, mirroring
  `BnestApp.ScheduledBackupTest`'s own `canonical_temporary_root/0` pattern
  (a real OS temp directory, never inside the repository checkout --
  `BnestApp.Backup.validate_destination/1` refuses any repository-internal
  directory other than its own default). Lives under `test/support/` (not
  `test/unit/`), so calling it from the unit behaviour driver does not trip
  the unit-layer `File`/`System` boundary scan (`test/behaviour/verify.exs`)
  -- the driver only calls into this and into `BnestApp.Backup.run/1`'s
  `:destination_directory` option, never touching `File`/`System` in its own
  source.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Backup

  @spec create!(String.t()) :: %{directory: String.t()}
  def create!(tag) when is_binary(tag) do
    # `System.tmp_dir!/0` can itself be reached through a symlink (macOS's
    # `/var` -> `/private/var`, which its default TMPDIR sits under) --
    # `Backup.validate_destination/1` refuses any destination reached through a
    # symlink, so this resolves the real path first, exactly like
    # `BnestApp.ScheduledBackupTest`'s own `canonical_temporary_root/0`.
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    root = String.trim(resolved)
    directory = Path.join(root, "bnest-backup-test-#{tag}-#{unique_id()}")
    File.mkdir_p!(directory)
    %{directory: directory}
  end

  @doc """
  Makes an isolated destination the configured backup destination until the calling test
  exits: `BNEST_BACKUP_CONFIG` points at a configuration file beside it, which
  `BnestApp.Backup.save_destination/1` writes through the file configuration store, so the
  Backup task the Scheduler runs resolves it and never the real
  `~/.config/bnest/backup.json`. Returns the saved location. Integration layer only: the
  unit layer's configuration store is in memory.
  """
  @spec configure!(String.t()) :: map()
  def configure!(tag) when is_binary(tag) do
    %{directory: root} = destination = create!(tag)
    previous = System.get_env("BNEST_BACKUP_CONFIG")
    System.put_env("BNEST_BACKUP_CONFIG", Path.join(root, "configuration/backup.json"))

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: System.put_env("BNEST_BACKUP_CONFIG", previous),
        else: System.delete_env("BNEST_BACKUP_CONFIG")

      cleanup!(destination)
    end)

    {:ok, location} = Backup.save_destination(Path.join(root, "destination"))
    location
  end

  @doc """
  Makes `repository` the backup repository root until the calling test exits, so Backup's
  unconfigured default destination is its `data/backup`. `config/test.exs` gives every test
  run a root that is no git repository, so that default fails closed; this replaces it only
  for a test that needs a working default, and restores it afterwards. Integration layer only.
  """
  @spec use_repository_root!(String.t()) :: :ok
  def use_repository_root!(repository) when is_binary(repository) do
    previous = Application.fetch_env(:bnest_app, :backup_repository_root)
    Application.put_env(:bnest_app, :backup_repository_root, repository)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, root} -> Application.put_env(:bnest_app, :backup_repository_root, root)
        :error -> Application.delete_env(:bnest_app, :backup_repository_root)
      end
    end)
  end

  @doc """
  Creates an isolated git repository that ignores its `data/` in an OS temporary directory,
  never inside a checkout, and makes it the backup repository root until the calling test
  exits (`use_repository_root!/1`). Returns its default destination directory.
  """
  @spec default_repository!(String.t()) :: String.t()
  def default_repository!(tag) when is_binary(tag) do
    %{directory: root} = destination = create!("repository-" <> tag)
    ExUnit.Callbacks.on_exit(fn -> cleanup!(destination) end)
    File.write!(Path.join(root, ".gitignore"), "/data/*\n")
    {_output, 0} = System.cmd("git", ["init", "--quiet", root])
    :ok = use_repository_root!(root)
    Path.join(root, "data/backup")
  end

  @spec cleanup!(map()) :: :ok
  def cleanup!(%{directory: directory}) do
    File.rm_rf(directory)
    :ok
  end

  defp unique_id, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
