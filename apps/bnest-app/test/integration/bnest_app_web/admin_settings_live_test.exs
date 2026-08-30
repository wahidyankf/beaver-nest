defmodule BnestAppWeb.AdminSettingsLiveTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BnestApp.Release.Migrations.PersistentSchedules

  @now ~U[2026-08-30 20:00:00Z]

  setup do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    temporary_root = canonical_temporary_root()
    config_path = Path.join(temporary_root, "bnest-admin-settings-#{suffix}/backup.json")
    System.put_env("BNEST_BACKUP_CONFIG", config_path)
    :ok = PersistentSchedules.apply_and_verify!(@now)

    on_exit(fn ->
      System.delete_env("BNEST_BACKUP_CONFIG")
      File.rm_rf(Path.dirname(config_path))
    end)

    :ok
  end

  test "admin discovers typed panels and the grouped schedule inventory", %{conn: conn} do
    {:ok, settings, _html} = live(conn, "/admin/settings")
    assert has_element?(settings, "a[href='/storage']", "Data storage")
    assert has_element?(settings, "a[href='/admin/settings/schedules']", "Schedules & backups")

    {:ok, schedules, _html} = live(conn, "/admin/settings/schedules")
    assert has_element?(schedules, "#family-schedules-title", "Family schedules")
    assert has_element?(schedules, "#admin-schedules-title", "Admin/system schedules")

    assert has_element?(
             schedules,
             "[data-schedule-key='prod-sqlite-backup-daily']",
             "Never run"
           )
  end

  test "schedule and backup owners reject invalid fields independently", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/settings/schedules")

    view
    |> form("form[phx-submit='save_schedule']", %{
      "schedule" => %{"daily_time_wib" => "99:99", "enabled" => "true", "revision" => "1"}
    })
    |> render_submit()

    assert has_element?(view, "#settings-error", "Enter a valid WIB time.")

    view
    |> form("form[phx-submit='save_backup']", %{
      "backup" => %{"destination_directory" => "relative/backup"}
    })
    |> render_submit()

    assert has_element?(view, "#settings-error", "could not be saved safely")
    assert has_element?(view, "input[name='schedule[daily_time_wib]'][value='02:00']")
  end

  test "non-admin route denial happens before either settings surface renders", %{conn: conn} do
    {child_conn, _identity} =
      scenario_authenticated_conn(conn, "admin-settings-denial", ["children"])

    assert child_conn |> get("/admin/settings") |> response(404)
    assert child_conn |> get("/admin/settings/schedules") |> response(404)
  end

  defp canonical_temporary_root do
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    String.trim(resolved)
  end
end
