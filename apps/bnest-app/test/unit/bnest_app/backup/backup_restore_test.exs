defmodule BnestApp.BackupRestoreTest do
  # `async: false`: Backup reaches the in-memory adapters the test installs under their
  # module names, as the unit layer's configuration selects them.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.FamilyChat
  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore
  alias BnestApp.Test.InMemory.CapacityProbe
  alias BnestApp.Test.InMemory.DatabaseSnapshot
  alias BnestApp.Test.InMemory.IgnoreCheck
  alias BnestApp.Test.InMemory.RoomStore

  @deadline ~U[2026-09-18 00:00:00Z]
  @destination "/srv/test-user-backup/restore-archived-room"

  setup do
    rooms = RoomStore.install()
    _artifacts = ArtifactStore.install()
    _snapshot = DatabaseSnapshot.install()
    _capacity = CapacityProbe.install()
    _ignore = IgnoreCheck.install()
    _config = BackupConfigStore.install()
    %{rooms: rooms}
  end

  describe "restore evidence" do
    test "names the active room even when an archived room exists", %{rooms: rooms} do
      # An archived second room like the one the reply behaviour scenarios use for their
      # cross-room refusal case, so the room list keeps reporting exactly one active room.
      archived = %{
        FamilyChat.canonical_room()
        | id: 900,
          slug: "ruang-arsip",
          name: "Ruang Arsip"
      }

      :ok = RoomStore.put_room(rooms, archived, deleted?: true)
      {:ok, _location} = Backup.save_destination(@destination)

      {:ok, artifact} = Backup.run(deadline: @deadline, destination_directory: @destination)

      assert {:ok, %{evidence: evidence}} = Backup.restore(artifact)
      assert %{"room" => room} = Jason.decode!(evidence)
      assert room["slug"] == FamilyChat.canonical_room_slug()
      refute room["slug"] == "ruang-arsip"
    end
  end
end
