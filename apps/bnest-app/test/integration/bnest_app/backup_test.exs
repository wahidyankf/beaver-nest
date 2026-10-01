defmodule BnestApp.BackupTest do
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.Storage.Adapters.FileRecordExport
  alias BnestApp.Storage.Records

  test "preserves exact legacy bytes idempotently and detects immutable collisions" do
    store = Records.store()
    owner = {:app, "beaver-nest"}
    import_id = "import-synthetic-backup"
    bytes = <<0, 1, 2, 255, 10>>

    assert {:ok, receipt} = FileRecordExport.preserve(store, owner, import_id, bytes)
    assert {:ok, ^bytes} = FileRecordExport.read(store, owner, import_id, receipt.sha256)
    assert {:ok, ^receipt} = FileRecordExport.preserve(store, owner, import_id, bytes)

    assert {:error, :immutable_collision} =
             FileRecordExport.preserve(store, owner, import_id, "changed")

    assert {:error, :checksum_mismatch} =
             FileRecordExport.read(store, owner, import_id, String.duplicate("0", 64))
  end

  test "keeps user recovery bytes below their server-selected owner" do
    store = Records.store()
    bytes = "synthetic legacy user bytes"

    assert {:ok, receipt} =
             FileRecordExport.preserve(
               store,
               {:user, "user-synthetic"},
               "import-user-backup",
               bytes
             )

    assert receipt.relative_path ==
             "users/user-synthetic/legacy/import-user-backup/source.bin"

    assert {:ok, ^bytes} =
             FileRecordExport.read(
               store,
               {:user, "user-synthetic"},
               "import-user-backup",
               receipt.sha256
             )
  end
end
