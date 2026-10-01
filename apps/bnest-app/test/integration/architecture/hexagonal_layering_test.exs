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
    BnestApp.Chat,
    BnestApp.Codex.ModelAccess,
    BnestApp.Codex.ModelCatalog,
    BnestApp.Codex.ModelDiscovery,
    BnestApp.Codex.PortSession,
    BnestApp.Codex.RepositoryAccess,
    BnestApp.Codex.Settings,
    BnestApp.Deployment,
    BnestApp.FamilyChat,
    BnestApp.FamilyChat.Store,
    BnestApp.Identity,
    BnestApp.Identity.Session,
    BnestApp.PushNotifications,
    BnestApp.PushNotifications.Dispatcher,
    BnestApp.PushNotifications.Sender,
    BnestApp.Scheduler,
    BnestApp.Scheduler.Policy,
    BnestApp.Scheduler.Registry,
    BnestApp.Scheduler.Run,
    BnestApp.Scheduler.Store,
    BnestApp.SifatAllah,
    BnestAppWeb.HealthController
  ]

  # Temporary. Inbound adapters still reading `BnestApp.Storage.Records` directly.
  @legacy_records_callers [
    # U8: the chat transcript moves behind CodexChat.
    BnestAppWeb.ChatLive,
    # U7: learning progress moves behind SifatAllah.
    BnestAppWeb.SifatAllahLive,
    # U6: the theme preference moves behind Preferences.
    BnestAppWeb.ThemeController,
    # U6: the theme read moves behind Preferences.
    BnestAppWeb.UserAuth
  ]

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
