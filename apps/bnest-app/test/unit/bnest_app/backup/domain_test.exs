defmodule BnestApp.Backup.DomainTest do
  use ExUnit.Case, async: true

  alias BnestApp.Backup.Domain.Location
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Backup.Domain.Retention

  @now ~U[2026-09-18 00:00:00Z]
  @digest String.duplicate("a", 64)

  describe "Receipt.valid?/2" do
    setup do
      claim = %{
        schedule_key: "prod-sqlite-backup-daily",
        claim_kind: "scheduled",
        claim_key: "scheduled:2026-09-18",
        scheduled_for: @now,
        run_id: "run-1",
        schedule_revision: 1
      }

      artifact = %{
        source_generation: "generation-1",
        basename: "bnest-prod-20260918T000000Z-run.sqlite3",
        sha256: @digest,
        bytes: 42,
        quick_check: "ok",
        schema_versions: [1],
        logical_proof_sha256: @digest
      }

      location = %{
        directory: "/srv/test-user-backup/destination",
        destination_id: "destination-1"
      }

      %{receipt: Receipt.build(claim, location, @now, artifact)}
    end

    test "accepts the receipt it builds, for its own destination only", %{receipt: receipt} do
      assert receipt["scheduledFor"] == "2026-09-18T00:00:00Z"
      assert Receipt.valid?(receipt, "destination-1")
      refute Receipt.valid?(receipt, "destination-2")
    end

    test "refuses what is no receipt, a nested basename and an unreadable instant",
         %{receipt: receipt} do
      refute Receipt.valid?(["not", "a", "receipt"], "destination-1")
      refute Receipt.valid?(%{receipt | "artifactBasename" => 42}, "destination-1")

      refute Receipt.valid?(
               %{receipt | "artifactBasename" => "nested/a.sqlite3"},
               "destination-1"
             )

      refute Receipt.valid?(%{receipt | "createdAt" => 42}, "destination-1")

      refute Receipt.valid?(
               %{receipt | "createdAt" => "2026-09-18T07:00:00+07:00"},
               "destination-1"
             )
    end

    test "places the receipt beside its artifact" do
      assert Receipt.path("/srv/test-user-backup/a.sqlite3") ==
               "/srv/test-user-backup/a.receipt.json"
    end
  end

  describe "Retention" do
    test "keeps the newest receipt of each of the seven latest WIB dates" do
      receipts =
        for days <- 0..8, minutes <- [0, 30] do
          %{
            "runId" => "run-#{days}-#{minutes}",
            "createdAt" =>
              @now |> DateTime.add(-days * 86_400 + minutes * 60) |> DateTime.to_iso8601()
          }
        end

      kept = receipts |> Retention.newest_first() |> Retention.retained_run_ids()
      assert kept == MapSet.new(0..6, &"run-#{&1}-30")
    end

    test "groups by the WIB date, seven hours ahead of UTC" do
      late_utc = %{"runId" => "late", "createdAt" => "2026-09-17T17:00:00Z"}
      early_utc = %{"runId" => "early", "createdAt" => "2026-09-17T16:59:59Z"}

      assert Retention.retained_run_ids([late_utc, early_utc]) == MapSet.new(["late", "early"])
    end

    test "refuses an instant that is not UTC" do
      assert_raise ArgumentError, "expected a UTC ISO 8601 instant", fn ->
        Retention.retained_run_ids([
          %{"runId" => "run", "createdAt" => "2026-09-18T07:00:00+07:00"}
        ])
      end
    end
  end

  describe "Location.valid_marker?/1" do
    test "accepts a marker it creates and refuses one with an unreadable instant" do
      marker = Location.new_marker(String.duplicate("i", 22), @now)

      assert Location.valid_marker?(marker)
      refute Location.valid_marker?(%{marker | "createdAt" => 42})
      refute Location.valid_marker?(%{marker | "destinationId" => "short"})
    end
  end
end
