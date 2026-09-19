defmodule BnestApp.FamilyChatMigrationTest do
  use ExUnit.Case, async: false

  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("family-chat-migration")

    # `BnestApp.FamilyChat.Store` (see `config/test.exs`) always resolves its
    # own connection via `family_chat_sqlite_path`, derived from
    # `BNEST_TEST_RUN_ID`, independent of `BNEST_STORAGE_CONFIG` -- by
    # design, so Family Chat's tests never resolve through the
    # shared/production storage pointer. Every eval below pins
    # `BNEST_TEST_RUN_ID` to this test's own run id and points
    # `BNEST_STORAGE_CONFIG` at the exact directory that same id resolves
    # to, so `PersistentSchedules` (which reads `BNEST_STORAGE_CONFIG`) and
    # `FamilyChat` (which reads `family_chat_sqlite_path`) share one
    # physical file instead of silently diverging mid-sequence.
    family_chat_dir = Path.expand("~/bnest/data/test/family-chat/#{runtime.run_id}")

    on_exit(fn ->
      File.rm_rf!(family_chat_dir)
      TestRuntimeRoot.cleanup!(runtime)
    end)

    {:ok, runtime: runtime, family_chat_dir: family_chat_dir}
  end

  test "starts database dependencies and owns the repo for a standalone converge_after_drain! release eval",
       %{runtime: runtime, family_chat_dir: family_chat_dir} do
    storage_config_path = Path.join(runtime.path, "release-storage.json")

    File.write!(
      storage_config_path,
      JSON.encode!(%{
        "schemaVersion" => 1,
        "databaseDirectory" => family_chat_dir,
        "databaseFilename" => "bnest.sqlite3",
        "phase" => "sqlite_primary",
        "migrationId" => "flat-files-v1-to-sqlite-v1"
      })
    )

    env = [
      {"MIX_ENV", "test"},
      {"BNEST_TEST_LAYER", "unit"},
      {"BNEST_TEST_RUN_ID", runtime.run_id},
      {"BNEST_STORAGE_CONFIG", storage_config_path}
    ]

    project_root = Path.expand("../../..", __DIR__)

    # Every step gets its own `mix run --no-start` eval -- each its own
    # fresh, non-supervised BEAM node -- mirroring the real deployment
    # shape, where `release:migrate` and `release:converge` are each a
    # separate `bin/bnest_app eval` invocation. Every check below also runs
    # *inside* a standalone eval rather than through this test process's own
    # live, supervised `Scheduler` GenServer, which would otherwise race to
    # claim/reap the very rows under test (the same shared-state hazard
    # already documented elsewhere in this suite).
    run_eval! = fn expression ->
      {output, status} =
        System.cmd("mix", ["run", "--no-start", "--no-compile", "-e", expression],
          cd: project_root,
          env: env,
          stderr_to_stdout: true
        )

      assert status == 0, output
    end

    run_eval!.(
      ":ok = BnestApp.Release.Migrations.PersistentSchedules.apply_and_verify!(DateTime.utc_now())"
    )

    run_eval!.(":ok = BnestApp.Release.Migrations.FamilyChat.apply_and_verify!()")

    run_eval!.("""
    :ok = BnestApp.Release.Migrations.FamilyChat.converge_after_drain!()
    if Process.whereis(BnestApp.SqliteRepo), do: raise("standalone convergence retained repo")
    """)

    run_eval!.("""
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:exqlite)
    :ok = BnestApp.DataRepository.StorageCoordinator.ensure_started!()

    case BnestApp.SqliteRepo.query!(
           "SELECT daily_at_utc, enabled FROM bnest_schedules WHERE schedule_key = ?",
           ["prod-sqlite-backup-daily"]
         ) do
      %{rows: [["18:00", 1]]} -> :ok
      other -> raise "backup schedule not converged: " <> inspect(other)
    end

    case BnestApp.SqliteRepo.query!(
           "SELECT enabled FROM bnest_schedules WHERE schedule_key = ?",
           ["family-chat-push-retention-daily"]
         ) do
      %{rows: [[1]]} -> :ok
      other -> raise "retention schedule not enabled: " <> inspect(other)
    end
    """)
  end
end
