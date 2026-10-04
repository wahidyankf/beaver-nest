defmodule BnestApp.BackupTest do
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Storage.Adapters.FileRecordExport
  alias BnestApp.Storage.Records
  alias BnestApp.TestBackupDestination

  @foreign_destination_id String.duplicate("F", 22)

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

  describe "retention beside files the destination does not own" do
    # Eight owned dates sit beside a foreign destination's receipts that, if retention counted
    # them, would change what it keeps: one is newer than the owned run of its date (2030-05-15),
    # one is newer than every owned date, one is older than the owned run of its date. An
    # artifact without a receipt and malformed receipts sit beside them, inside and outside the
    # window. Retention must remove the oldest owned pair and change nothing else. Retention
    # keeps by WIB (UTC+07:00) date: an owned run is created at 03:00 UTC, 10:00 WIB of the same
    # date, so the owned dates are 2030-05-11 to 2030-05-18.
    test "removes exactly the owned pairs outside the seven latest dates and nothing else" do
      %{directory: directory} = location = TestBackupDestination.configure!("retention")
      foreign_location = %{location | destination_id: @foreign_destination_id}

      owned =
        for day <- 11..18,
            do:
              write_pair!(
                directory,
                location,
                "owned-203005#{day}",
                created_at(day, ~T[03:00:00])
              )

      foreign = [
        write_pair!(
          directory,
          foreign_location,
          "foreign-newer-20300515",
          created_at(15, ~T[05:00:00])
        ),
        write_pair!(
          directory,
          foreign_location,
          "foreign-latest-20300519",
          created_at(19, ~T[03:00:00])
        ),
        write_pair!(
          directory,
          foreign_location,
          "foreign-older-20300514",
          created_at(14, ~T[01:00:00])
        )
      ]

      File.write!(
        Path.join(directory, "bnest-prod-20300510T030000Z-test-unreceipted-old.sqlite3"),
        "synthetic"
      )

      File.write!(
        Path.join(directory, "bnest-prod-20300518T050000Z-test-unreceipted-new.sqlite3"),
        "synthetic"
      )

      malformed = Path.join(directory, "bnest-prod-malformed.sqlite3")
      File.write!(malformed, "synthetic malformed pair")
      File.write!(Receipt.path(malformed), ~s({"schemaVersion":1}))
      unreadable = Path.join(directory, "bnest-prod-unreadable.sqlite3")
      File.write!(unreadable, "synthetic unreadable pair")
      File.write!(Receipt.path(unreadable), "{not json")

      # The foreign receipts are whole and match their artifacts: only their destination makes
      # them foreign, so a retention that counted them would act on them.
      for pair <- foreign do
        receipt = directory |> Path.join(pair.receipt) |> File.read!() |> Jason.decode!()

        assert Receipt.valid?(receipt, @foreign_destination_id)
        refute Receipt.valid?(receipt, location.destination_id)
      end

      oldest = hd(owned)
      before = listing(directory)
      assert Map.has_key?(before, oldest.artifact) and Map.has_key?(before, oldest.receipt)

      # The receipts retention judges are the eight owned runs, newest first.
      assert run_ids(Backup.owned_receipts(directory)) ==
               owned |> Enum.reverse() |> Enum.map(& &1.run_id)

      assert {:ok, kept} = Backup.retain_owned(directory)

      kept_runs = tl(owned)
      assert kept == MapSet.new(kept_runs, & &1.run_id)

      # A newer foreign receipt shares the date of the owned run of 2030-05-15, which stays.
      superseded = Enum.find(owned, &(&1.artifact =~ "owned-20300515"))
      assert MapSet.member?(kept, superseded.run_id)
      assert Map.has_key?(listing(directory), superseded.artifact)

      assert listing(directory) == Map.drop(before, [oldest.artifact, oldest.receipt])

      assert run_ids(Backup.owned_receipts(directory)) ==
               kept_runs |> Enum.reverse() |> Enum.map(& &1.run_id)
    end
  end

  # A verified pair as a backup run leaves it: the artifact and the receipt beside it, naming
  # `location` as its destination and `created_at` as its instant.
  defp write_pair!(directory, location, label, %DateTime{} = created_at) do
    basename =
      "bnest-prod-#{Calendar.strftime(created_at, "%Y%m%dT%H%M%SZ")}-test-#{label}.sqlite3"

    path = Path.join(directory, basename)
    content = "synthetic backup #{label}"
    File.write!(path, content)

    artifact = %{
      path: path,
      basename: basename,
      sha256: sha256(content),
      bytes: byte_size(content),
      quick_check: "ok",
      schema_versions: [1],
      logical_proof_sha256: sha256(basename),
      source_generation: nil
    }

    claim = %{
      schedule_key: "test-schedule-retention",
      claim_kind: "scheduled",
      claim_key: "slot:" <> label,
      scheduled_for: created_at,
      run_id: "test-run-" <> label,
      schedule_revision: 1
    }

    {:ok, receipt} = Backup.record_receipt(claim, location, created_at, artifact)
    %{run_id: receipt["runId"], artifact: basename, receipt: Path.basename(Receipt.path(path))}
  end

  defp created_at(day, time), do: DateTime.new!(Date.new!(2030, 5, day), time, "Etc/UTC")

  # Every file of `directory`, dotfiles included, by name with its bytes.
  defp listing(directory) do
    Map.new(File.ls!(directory), &{&1, File.read!(Path.join(directory, &1))})
  end

  defp run_ids(receipts), do: Enum.map(receipts, & &1["runId"])

  defp sha256(content), do: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)
end
