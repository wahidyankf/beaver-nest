defmodule BnestApp.HexagonalLayeringTest do
  use ExUnit.Case, async: true

  alias BnestApp.ArchitectureScan

  # Temporary. Modules not yet moved into a context's layers, whose violations the scan
  # tolerates. Each context unit deletes its entries; the closure unit requires it empty.
  @legacy_modules [
    BnestApp.AdminConfig.Registry,
    BnestApp.Backup,
    BnestApp.Backup.Capacity,
    BnestApp.Backup.Config,
    BnestApp.Backup.Location,
    BnestApp.Backup.Run,
    BnestApp.Deployment,
    BnestApp.PushNotifications,
    BnestApp.PushNotifications.Dispatcher,
    BnestApp.PushNotifications.Sender,
    BnestApp.Scheduler,
    BnestApp.Scheduler.Policy,
    BnestApp.Scheduler.Registry,
    BnestApp.Scheduler.Run,
    BnestApp.Scheduler.Store,
    BnestAppWeb.HealthController
  ]

  # Temporary. Inbound adapters still reading `BnestApp.Storage.Records` directly.
  @legacy_records_callers []

  test "effects stay in adapters, domains stay pure, and inbound adapters call only facades" do
    violations =
      [records_callers: @legacy_records_callers]
      |> ArchitectureScan.violations()
      |> Enum.reject(&(&1.module in @legacy_modules))

    assert violations == [], ArchitectureScan.format(violations)
  end

  test "every legacy export of the root boundary is a legacy module" do
    assert ArchitectureScan.legacy_exports() -- @legacy_modules == []
  end

  test "every legacy module still exists" do
    assert @legacy_modules -- ArchitectureScan.defined_modules() == []
  end
end
