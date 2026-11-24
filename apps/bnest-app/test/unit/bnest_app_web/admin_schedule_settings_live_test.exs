defmodule BnestAppWeb.AdminScheduleSettingsLiveTest do
  @moduledoc """
  Unit tests for the `scheduled_backups.feature` refusal scenarios. The production
  `AdminScheduleSettingsLive` runs over the Scheduler facade and the Backup facade's
  in-memory ports, so a bad time, a stale revision and each bad folder take the same
  path the administrator's browser triggers, without touching the disk.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore
  alias BnestApp.Test.InMemory.CapacityProbe
  alias BnestApp.Test.InMemory.DatabaseSnapshot
  alias BnestApp.Test.InMemory.IgnoreCheck
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestAppWeb.AdminScheduleSettingsLive
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.Socket

  @now ~U[2026-08-30 20:00:00Z]
  @key "prod-sqlite-backup-daily"
  @admin %{
    "userId" => "test-user-unit-admin",
    "displayUsername" => "test-user-unit-admin",
    "roles" => ["admin"]
  }

  setup do
    InMemoryScheduleStore.install()
    BackupConfigStore.install()
    ArtifactStore.install()
    DatabaseSnapshot.install()
    CapacityProbe.install()
    IgnoreCheck.install()
    start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})

    :ok =
      InMemoryScheduleStore.put_daily_schedule(
        Scheduler.store(),
        @key,
        "prod_sqlite_backup",
        "admin_system",
        @now
      )

    :ok
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: A bad schedule time says "Enter a valid WIB time."
  test "a bad schedule time says Enter a valid WIB time and keeps the saved schedule" do
    {:ok, saved} = save_daily("02:00")
    {:ok, socket} = mount_schedules()

    {:noreply, refused} =
      AdminScheduleSettingsLive.handle_event(
        "save_schedule",
        %{
          "schedule" => %{
            "daily_time_wib" => "25:00",
            "enabled" => "true",
            "revision" => Integer.to_string(saved.revision)
          }
        },
        socket
      )

    assert error_text(refused) == "Enter a valid WIB time."
    assert Scheduler.get_schedule(@key) == saved
    assert render(refused) |> LazyHTML.query(".admin-settings-status") |> Enum.empty?()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: A stale schedule save says to reload and try again
  test "a stale schedule save says to reload and try again" do
    {:ok, saved} = save_daily("02:00")
    {:ok, socket} = mount_schedules()

    {:ok, rival} =
      Scheduler.update_daily(
        @key,
        %{"daily_time_wib" => "04:00", "enabled" => "true", "revision" => "#{saved.revision}"},
        @now
      )

    {:noreply, refused} =
      AdminScheduleSettingsLive.handle_event(
        "save_schedule",
        %{
          "schedule" => %{
            "daily_time_wib" => "03:00",
            "enabled" => "true",
            "revision" => "#{saved.revision}"
          }
        },
        socket
      )

    assert error_text(refused) == "The schedule changed. Reload and try again."
    assert Scheduler.get_schedule(@key) == rival
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: A bad backup folder gets a plain refusal reason
  test "a bad backup folder gets a plain refusal reason" do
    :ok = ArtifactStore.put_symlink(ArtifactStore.new(), "/srv/test-user-backup/link")

    for {folder, message} <- [
          {"/srv/test-user-backup/database/backups",
           "Choose a folder outside the live database location."},
          {"/srv/test-user-backup/link/backups", "Choose a folder that is not a symbolic link."},
          {"relative/backup", "The backup folder could not be saved safely."}
        ] do
      {:ok, socket} = mount_schedules()

      {:noreply, refused} =
        AdminScheduleSettingsLive.handle_event(
          "save_backup",
          %{"backup" => %{"destination_directory" => folder}},
          socket
        )

      assert error_text(refused) == message
      assert match?({:error, :absent}, BackupConfigStore.read(BackupConfigStore.new()))
      assert InMemoryScheduleStore.runs(Scheduler.store()) == []
      assert render(refused) |> LazyHTML.query(".admin-settings-status") |> Enum.empty?()
    end
  end

  defp save_daily(time) do
    Scheduler.update_daily(
      @key,
      %{"daily_time_wib" => time, "enabled" => "true", "revision" => "1"},
      @now
    )
  end

  defp mount_schedules do
    socket = %Socket{
      view: AdminScheduleSettingsLive,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: @admin}
    }

    AdminScheduleSettingsLive.mount(%{}, %{}, socket)
  end

  defp render(socket) do
    socket.assigns
    |> Map.delete(:__changed__)
    |> AdminScheduleSettingsLive.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  defp error_text(socket) do
    socket |> render() |> LazyHTML.query("#settings-error") |> LazyHTML.text() |> String.trim()
  end
end
