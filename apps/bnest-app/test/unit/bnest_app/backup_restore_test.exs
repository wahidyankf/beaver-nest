defmodule BnestApp.BackupRestoreTest do
  # `async: false`: shares the real singleton SQLite database with the rest of
  # the unit suite, and selects the SQLite room store application-wide.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.FamilyChat
  alias BnestApp.SqliteRepo
  alias BnestApp.Test.LegacySqliteRoomStore
  alias BnestApp.TestBackupDestination

  @deadline ~U[2026-09-18 00:00:00Z]

  # The backup snapshots Family Chat's SQLite database until U12.
  setup do
    LegacySqliteRoomStore.select!()
  end

  describe "restore evidence" do
    test "names the active room even when an archived room exists" do
      seed_archived_room!()
      destination = TestBackupDestination.create!("restore-archived-room")
      on_exit(fn -> TestBackupDestination.cleanup!(destination) end)

      {:ok, artifact} =
        Backup.run(deadline: @deadline, destination_directory: destination.directory)

      assert {:ok, %{evidence: evidence}} = Backup.restore(artifact)
      assert %{"room" => room} = Jason.decode!(evidence)
      assert room["slug"] == FamilyChat.canonical_room_slug()
      refute room["slug"] == "ruang-arsip"
    end
  end

  # An archived second room like the one the reply behaviour scenarios use for
  # their cross-room refusal case. Soft-deleted from the start so the room list
  # keeps reporting exactly one active room; `INSERT OR IGNORE` plus a fixed ID
  # keeps repeated runs idempotent.
  defp seed_archived_room! do
    FamilyChat.ensure_ready!()
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO family_chat_rooms (
        id, slug, name, room_kind, member_posting_enabled,
        created_at, created_by, updated_at, updated_by, deleted_at, deleted_by
      ) VALUES (900, 'ruang-arsip', 'Ruang Arsip', 'conversation', 1, ?, 'test', ?, 'test', ?, 'test')
      """,
      [now, now, now]
    )

    :ok
  end
end
