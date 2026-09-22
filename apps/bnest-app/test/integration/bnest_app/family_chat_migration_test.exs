defmodule BnestApp.FamilyChatMigrationTest do
  use ExUnit.Case, async: false

  alias BnestApp.FamilyChat.Store
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

  describe "additive reply column" do
    setup do
      Store.ensure_ready!()
      :ok
    end

    test "every message committed before the change reads as not a reply" do
      room = Store.get_active_room_by_slug("ruang-keluarga")

      {:ok, message} =
        Store.insert_message!(
          room.id,
          "user",
          "test-user-reply-migration",
          "Migration Probe",
          Ecto.UUID.generate(),
          "committed before the reply column existed"
        )

      %{rows: [[reply_to]]} =
        BnestApp.SqliteRepo.query!(
          "SELECT reply_to_message_id FROM family_chat_messages WHERE id = ?",
          [message.id]
        )

      assert reply_to == nil
    end

    test "the column is indexed only where it is set" do
      %{rows: rows} =
        BnestApp.SqliteRepo.query!(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
          ["family_chat_messages_reply_to"]
        )

      assert [[sql]] = rows
      assert sql =~ "WHERE reply_to_message_id IS NOT NULL"
    end

    test "re-running the migrator changes nothing" do
      before_schema = message_table_sql()

      Ecto.Migrator.run(
        BnestApp.SqliteRepo,
        Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations"),
        :up,
        all: true
      )

      assert message_table_sql() == before_schema
    end

    # The reversal is exercised by calling `down/0` directly against a
    # database that already holds a reply, rather than by rolling the real
    # migrator back: the point is the refusal, and a migrator rollback that
    # succeeded would destroy the row the refusal exists to protect.
    test "reversal refuses once a reply exists, and removes nothing" do
      room = Store.get_active_room_by_slug("ruang-keluarga")

      {:ok, original} =
        Store.insert_message!(
          room.id,
          "user",
          "test-user-reply-migration",
          "Migration Probe",
          Ecto.UUID.generate(),
          "the message being answered"
        )

      {:ok, reply} =
        Store.insert_message!(
          room.id,
          "user",
          "test-user-reply-migration",
          "Migration Probe",
          Ecto.UUID.generate(),
          "the answer",
          original.id
        )

      assert_raise RuntimeError, ~r/refuses to reverse/, fn ->
        Ecto.Migrator.run(
          BnestApp.SqliteRepo,
          Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations"),
          :down,
          to: 20_260_922_000_000
        )
      end

      %{rows: [[count]]} =
        BnestApp.SqliteRepo.query!(
          "SELECT COUNT(*) FROM family_chat_messages WHERE id = ?",
          [reply.id]
        )

      assert count == 1
    end
  end

  defp message_table_sql do
    %{rows: [[sql]]} =
      BnestApp.SqliteRepo.query!(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        ["family_chat_messages"]
      )

    sql
  end
end
