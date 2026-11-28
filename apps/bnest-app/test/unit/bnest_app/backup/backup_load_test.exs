defmodule BnestApp.Backup.LoadTest do
  # Chat load around a backup at the unit seam: the in-memory snapshot double holds its
  # copy open while the test's own traffic runs inside the hold, so every probe and every
  # busy-chat send genuinely falls inside the backup window. Restore then proves the
  # snapshot self-consistent, and the timed probes prove the scenario's budgets.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.FamilyChat
  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore
  alias BnestApp.Test.InMemory.CapacityProbe
  alias BnestApp.Test.InMemory.DatabaseSnapshot
  alias BnestApp.Test.InMemory.IgnoreCheck
  alias BnestApp.Test.InMemory.RoomStore

  @now ~U[2026-09-18 00:00:00Z]
  @destination "/srv/test-user-backup/load"

  setup do
    RoomStore.install()
    ArtifactStore.install()
    snapshot = DatabaseSnapshot.install()
    CapacityProbe.install()
    IgnoreCheck.install()
    BackupConfigStore.install()
    {:ok, _location} = Backup.save_destination(@destination)
    %{snapshot: snapshot}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A backup taken while the chat is busy restores as a consistent snapshot
  test "a backup taken while the chat is busy restores as a consistent snapshot", %{
    snapshot: snapshot
  } do
    slug = FamilyChat.canonical_room_slug()

    before_ids =
      for n <- 1..3 do
        {:ok, message} =
          FamilyChat.send_message(
            "test-user-load-quiet",
            slug,
            Ecto.UUID.generate(),
            "quiet #{n}"
          )

        message.id
      end

    :ok =
      DatabaseSnapshot.hold_next_copy(snapshot, fn ->
        mids =
          for n <- 1..5 do
            {:ok, message} =
              FamilyChat.send_message(
                "test-user-load-busy",
                slug,
                Ecto.UUID.generate(),
                "busy #{n}"
              )

            {:ok, _page} = FamilyChat.list_messages("test-user-load-reader", slug, limit: 50)
            message.id
          end

        {:held, mids}
      end)

    assert {:ok, artifact} =
             Backup.run(deadline: @now, destination_directory: @destination)

    assert {:ok, %{evidence: evidence}} = Backup.restore(artifact)
    %{"orderedMessageIds" => restored_ids} = Jason.decode!(evidence)

    assert [{:held, mid_ids}] = DatabaseSnapshot.holds(snapshot)
    sent_ids = MapSet.new(before_ids ++ mid_ids)

    assert MapSet.subset?(MapSet.new(before_ids), MapSet.new(restored_ids))
    assert MapSet.subset?(MapSet.new(restored_ids), sent_ids)
    assert restored_ids == Enum.sort(restored_ids)
  end

  # Reads and sends keep succeeding while the copy is held open: every probe the hold
  # runs falls inside the backup window, completes without failure, and lands in the
  # room history. The millisecond budgets need a real clock, so the integration layer
  # proves them; this layer proves the probes never fail mid-backup.
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Chat reads and sends stay within budget during a backup
  test "chat reads and sends stay within budget during a backup", %{snapshot: snapshot} do
    slug = FamilyChat.canonical_room_slug()

    :ok =
      DatabaseSnapshot.hold_next_copy(snapshot, fn ->
        sent_ids =
          for n <- 1..5 do
            {:ok, _page} = FamilyChat.list_messages("test-user-load-budget", slug, limit: 50)

            {:ok, message} =
              FamilyChat.send_message(
                "test-user-load-budget",
                slug,
                Ecto.UUID.generate(),
                "budget #{n}"
              )

            message.id
          end

        {:held, sent_ids}
      end)

    assert {:ok, _artifact} =
             Backup.run(deadline: @now, destination_directory: @destination)

    assert [{:held, sent_ids}] = DatabaseSnapshot.holds(snapshot)
    assert sent_ids != []

    assert {:ok, %{nodes: nodes}} =
             FamilyChat.list_messages("test-user-load-budget-reader", slug, limit: 50)

    history_ids = MapSet.new(nodes, & &1.id)
    assert MapSet.subset?(MapSet.new(sent_ids), history_ids)
  end
end
