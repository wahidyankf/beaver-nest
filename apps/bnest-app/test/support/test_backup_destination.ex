defmodule BnestApp.TestBackupDestination do
  @moduledoc """
  Test-only isolated backup destination, mirroring
  `BnestApp.ScheduledBackupTest`'s own `canonical_temporary_root/0` pattern
  (a real OS temp directory, never inside the repository checkout --
  `BnestApp.Backup.Location.validate/1` refuses any repository-internal
  directory other than its own default). Lives under `test/support/` (not
  `test/unit/`), so calling it from the unit behaviour driver does not trip
  the unit-layer `File`/`System` boundary scan (`test/behaviour/verify.exs`)
  -- the driver only calls into this and into `BnestApp.Backup.run/1`'s
  `:destination_directory` option, never touching `File`/`System` in its own
  source.
  """

  @spec create!(String.t()) :: %{directory: String.t()}
  def create!(tag) when is_binary(tag) do
    # `System.tmp_dir!/0` can itself be reached through a symlink (macOS's
    # `/var` -> `/private/var`, which its default TMPDIR sits under) --
    # `Location.validate/1` refuses any destination reached through a
    # symlink, so this resolves the real path first, exactly like
    # `BnestApp.ScheduledBackupTest`'s own `canonical_temporary_root/0`.
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    root = String.trim(resolved)
    directory = Path.join(root, "bnest-backup-test-#{tag}-#{unique_id()}")
    File.mkdir_p!(directory)
    %{directory: directory}
  end

  @spec cleanup!(map()) :: :ok
  def cleanup!(%{directory: directory}) do
    File.rm_rf(directory)
    :ok
  end

  defp unique_id, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
