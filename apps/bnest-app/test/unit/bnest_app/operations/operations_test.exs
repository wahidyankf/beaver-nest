defmodule BnestApp.Operations.FacadeTest do
  # `async: false`: the facade reaches the in-memory release environment the test installs
  # under its module name, as the unit layer's configuration selects it, and the Storage
  # doubles replace application-wide configuration.
  use ExUnit.Case, async: false

  alias BnestApp.Operations
  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.ReleaseEnvironment
  alias BnestApp.Test.InMemory.ScheduleStore
  alias BnestApp.Test.InMemory.StoragePorts

  @now ~U[2026-09-18 00:00:00Z]
  @readiness_processes [
    BnestApp.Storage.Records,
    BnestApp.Identity,
    BnestApp.CodexChat.ModelCatalog
  ]
  @sqlite_primary %{
    "schemaVersion" => 1,
    "databaseDirectory" => "/in-memory/bnest/data",
    "databaseFilename" => "bnest.sqlite3",
    "phase" => "sqlite_primary",
    "databaseGeneration" => "generation-test-user"
  }

  setup do
    environment = ReleaseEnvironment.install()
    Enum.each(@readiness_processes, &ReleaseEnvironment.put_running(environment, &1, true))
    %{environment: environment}
  end

  test "the unit layer reads the in-memory release environment, never the process environment" do
    assert Operations.adapter(:release_environment) == ReleaseEnvironment
  end

  describe "revision and slot" do
    test "default to development and standalone when the release names neither" do
      assert Operations.revision() == "development"
      assert Operations.slot() == "standalone"
    end

    test "are the release's own revision and deployment slot", %{environment: environment} do
      ReleaseEnvironment.put_revision(environment, "abc1234")
      ReleaseEnvironment.put_slot(environment, "blue")

      assert Operations.revision() == "abc1234"
      assert Operations.slot() == "blue"
    end
  end

  describe "liveness" do
    test "reports live with the revision and slot even when nothing else runs",
         %{environment: environment} do
      ReleaseEnvironment.put_revision(environment, "abc1234")
      ReleaseEnvironment.put_slot(environment, "green")
      Enum.each(@readiness_processes, &ReleaseEnvironment.put_running(environment, &1, false))
      ReleaseEnvironment.put_peer(environment, "bnest_blue@host", false)

      assert Operations.liveness() ==
               {:ok, %{status: "live", revision: "abc1234", slot: "green"}}
    end
  end

  describe "readiness" do
    test "is ready once the record repository, Identity and the model catalog run",
         %{environment: environment} do
      ReleaseEnvironment.put_revision(environment, "abc1234")
      ReleaseEnvironment.put_slot(environment, "blue")

      assert Operations.readiness() ==
               {:ok, %{status: "ready", revision: "abc1234", slot: "blue"}}

      assert ReleaseEnvironment.pinged(environment) == []
    end

    test "is not ready while any one of those processes is down", %{environment: environment} do
      for down <- @readiness_processes do
        Enum.each(@readiness_processes, &ReleaseEnvironment.put_running(environment, &1, true))
        ReleaseEnvironment.put_running(environment, down, false)

        assert Operations.readiness() == {:error, :not_ready}, inspect(down)
      end
    end

    test "checks the processes before the peer", %{environment: environment} do
      ReleaseEnvironment.put_running(environment, BnestApp.Identity, false)
      ReleaseEnvironment.put_peer(environment, "bnest_blue@host", false)

      assert Operations.readiness() == {:error, :not_ready}
      assert ReleaseEnvironment.pinged(environment) == []
    end

    test "needs a named peer to answer", %{environment: environment} do
      ReleaseEnvironment.put_peer(environment, "bnest_blue@host", true)
      assert {:ok, %{status: "ready"}} = Operations.readiness()

      ReleaseEnvironment.put_peer(environment, "bnest_green@host", false)
      assert Operations.readiness() == {:error, :peer_unavailable}

      assert ReleaseEnvironment.pinged(environment) == ["bnest_blue@host", "bnest_green@host"]
    end

    test "ignores an empty peer name", %{environment: environment} do
      ReleaseEnvironment.put_peer(environment, "", false)

      assert {:ok, %{status: "ready"}} = Operations.readiness()
      assert ReleaseEnvironment.pinged(environment) == []
    end
  end

  describe "health" do
    setup do
      previous = StoragePorts.install()
      on_exit(fn -> StoragePorts.restore(previous) end)
      :ok
    end

    test "while flat files are authoritative adds the storage state without touching SQLite",
         %{environment: environment} do
      ReleaseEnvironment.put_revision(environment, "abc1234")

      assert Operations.health() ==
               {:ok,
                %{
                  status: "ready",
                  revision: "abc1234",
                  slot: "standalone",
                  sqliteReady: false,
                  schedulerReady: false,
                  storageGeneration: nil
                }}

      assert StoragePorts.calls() == []
    end

    test "once SQLite is primary proves the seeded backup schedule under the shared lease" do
      StoragePorts.put(:config, @sqlite_primary)
      seed_backup_schedule(ScheduleStore.install())
      start_scheduler()

      assert Operations.health() ==
               {:ok,
                %{
                  status: "ready",
                  revision: "development",
                  slot: "standalone",
                  sqliteReady: true,
                  schedulerReady: true,
                  storageGeneration: "generation-test-user"
                }}

      assert StoragePorts.calls() == [:shared_lock, :ensure_started]
    end

    test "once SQLite is primary is not ready without the seeded backup schedule" do
      StoragePorts.put(:config, @sqlite_primary)
      ScheduleStore.install()
      start_scheduler()

      assert Operations.health() == {:error, :sqlite_not_ready}
    end

    test "once SQLite is primary refuses a backup schedule seeded for another handler or expiry" do
      StoragePorts.put(:config, @sqlite_primary)
      store = ScheduleStore.install()
      start_scheduler()

      for fields <- [%{handler_key: "fixture"}, %{expiration_kind: "after_occurrences"}] do
        seed_backup_schedule(store, fields)
        assert Operations.health() == {:error, :sqlite_not_ready}, inspect(fields)
      end
    end

    test "once SQLite is primary waits for the scheduler" do
      StoragePorts.put(:config, @sqlite_primary)
      seed_backup_schedule(ScheduleStore.install())

      assert Operations.health() == {:error, :scheduler_not_ready}
    end

    test "once SQLite is primary reports a failing database as not ready" do
      StoragePorts.put(:config, @sqlite_primary)

      # No schedule store is installed, so reading the backup schedule raises.
      assert Operations.health() == {:error, :sqlite_not_ready}
    end

    test "is not ready before readiness holds, and reads no storage", %{environment: environment} do
      StoragePorts.put(:config, @sqlite_primary)
      ReleaseEnvironment.put_peer(environment, "bnest_blue@host", false)

      assert Operations.health() == {:error, :peer_unavailable}
      assert StoragePorts.calls() == []
    end
  end

  describe "admin panels" do
    test "lists every declared panel with its owning context and editable fields" do
      assert Operations.admin_panels() == [
               %{
                 key: "data-storage",
                 label: "Data storage",
                 description: "Authoritative SQLite location and migration status",
                 path: "/storage",
                 owner: BnestApp.Storage,
                 editable_fields: []
               },
               %{
                 key: "schedules-backups",
                 label: "Schedules & backups",
                 description: "Daily jobs and verified production database backups",
                 path: "/admin/settings/schedules",
                 owner: BnestApp.Backup,
                 editable_fields: ["destination_directory", "enabled", "daily_time_wib"]
               }
             ]
    end

    test "fetches a panel by key" do
      assert {:ok, %{owner: BnestApp.Backup, path: "/admin/settings/schedules"}} =
               Operations.fetch_admin_panel("schedules-backups")

      assert {:ok, %{owner: BnestApp.Storage, path: "/storage"}} =
               Operations.fetch_admin_panel("data-storage")

      assert Operations.fetch_admin_panel("unknown-panel") == :error
    end
  end

  # Seeded as the release seeds it, but due only tomorrow, so the coordinator's boot tick
  # claims nothing.
  defp seed_backup_schedule(store, fields \\ %{}) do
    :ok =
      ScheduleStore.put_daily_schedule(
        store,
        "prod-sqlite-backup-daily",
        "prod_sqlite_backup",
        "admin_system",
        @now,
        Map.merge(%{next_run_at: DateTime.add(@now, 86_400)}, fields)
      )
  end

  defp start_scheduler do
    start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})
    start_supervised!({Scheduler, clock: fn -> @now end, automatic?: false})
  end
end
