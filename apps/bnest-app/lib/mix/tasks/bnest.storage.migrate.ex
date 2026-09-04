defmodule Mix.Tasks.Bnest.Storage.Migrate do
  @moduledoc false

  use Mix.Task

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig
  alias BnestApp.Storage.Lock, as: StorageLock
  alias BnestApp.Storage.Migration, as: StorageMigration

  @shortdoc "Runs the managed flat-file to SQLite storage migration without a browser visit"

  @impl Mix.Task
  def run(arguments) do
    Mix.Task.run("app.config")
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)
    {:ok, _apps} = Application.ensure_all_started(:exqlite)

    {options, remaining, invalid} =
      OptionParser.parse(arguments, strict: [root: :string, activate: :boolean])

    if remaining != [] or invalid != [] do
      Mix.raise("usage: mix bnest.storage.migrate [--root <flat-root>] [--activate]")
    end

    flat_root = options[:root] || Application.fetch_env!(:bnest_app, :runtime_root)
    activate? = Keyword.get(options, :activate, false)

    StorageLock.with_exclusive(fn -> migrate_and_maybe_activate!(flat_root, activate?) end)
  end

  defp migrate_and_maybe_activate!(flat_root, activate?) do
    config = StorageConfig.ensure_default!()
    database_path = Path.join(config["databaseDirectory"], config["databaseFilename"])

    :ok = StorageCoordinator.ensure_started!(database_path)

    {:ok, _versions, _apps} =
      Ecto.Migrator.with_repo(
        SqliteRepo,
        &Ecto.Migrator.run(&1, migrations_path(), :up, all: true)
      )

    result = StorageMigration.run(flat_root)

    Mix.shell().info(
      "migration #{result.migration_id}: accepted=#{result.accepted} blocked=#{result.blocked} " <>
        "unsupported=#{result.unsupported} state=#{result.state}"
    )

    cond do
      result.blocked > 0 or StorageMigration.blocked?() ->
        Mix.raise(
          "migration blocked: resolve the malformed or changed source, then retry with the same identifier"
        )

      not activate? ->
        Mix.shell().info(
          "dry run complete; rerun with --activate once ready to switch storage authority"
        )

      true ->
        verify_and_activate!(flat_root)
    end
  end

  defp verify_and_activate!(flat_root) do
    parity? = StorageMigration.parity_ok?(flat_root)
    integrity? = StorageMigration.integrity_ok?()
    restore? = restore_rehearsal_ok?()

    Mix.shell().info(
      "verification: parity=#{parity?} integrity=#{integrity?} restore=#{restore?}"
    )

    if parity? and integrity? and restore? do
      :ok = StorageMigration.activate!()
      Mix.shell().info("storage authority switched to sqlite_primary")
    else
      Mix.raise("verification failed; SQLite storage was not activated")
    end
  end

  defp restore_rehearsal_ok? do
    destination =
      Path.join(
        System.tmp_dir!(),
        "bnest-storage-restore-rehearsal-#{System.unique_integer([:positive])}.sqlite3"
      )

    StorageMigration.restore_rehearsal(destination)
  end

  defp migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
end
