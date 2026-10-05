defmodule BnestAppWeb.AdminSettingsLiveTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Test.BackupIntegrity
  alias BnestApp.Test.CallTrace
  alias BnestApp.Test.IntegrityLabel
  alias BnestApp.Test.ObservedArtifactStore
  alias BnestApp.TestBackupDestination

  @now ~U[2026-08-30 20:00:00Z]
  @route "/admin/settings/schedules"

  # The ceiling the label's check is lowered to where a test waits for it: long enough to read
  # the first renders before it, short enough to keep the test brief.
  @ceiling_ms 1_000

  # The exact copy of the plan's States and Real Copy table, written out here so no check calls
  # the wording function it verifies.
  @checking "checking"
  @could_not_check "could not be checked. Reload this page to try again."
  @nothing_to_check "no verified backup to check yet"
  @all_present "all 7 retained backups are present"

  # Every call by which a page could open the ledger's verified runs or read the destination's
  # artifacts: none may run on a disconnected render or for a denied visitor.
  @check_calls [
    {{BnestApp.Scheduler, :verified_runs, 1}, []},
    {{BnestApp.Backup, :reconcile, 2}, []},
    {{BnestApp.Backup, :read_destination, 0}, []},
    {{BnestApp.Backup.Ports.ArtifactStore, :regular?, 2}, []},
    {{BnestApp.Backup.Ports.ArtifactStore, :digest, 2}, []},
    {{BnestApp.Backup.Ports.ArtifactStore, :size, 2}, []}
  ]

  setup do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    temporary_root = canonical_temporary_root()
    config_path = Path.join(temporary_root, "bnest-admin-settings-#{suffix}/backup.json")
    System.put_env("BNEST_BACKUP_CONFIG", config_path)
    # The schedules page shows the unconfigured default destination; the test run's own
    # repository root fails closed, so it gets an isolated working one.
    _default = TestBackupDestination.default_repository!("admin-settings-#{suffix}")
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
             "[data-schedule-key='prod-sqlite-backup-daily']" <>
               ":is([data-last-run-state='never'], [data-last-run-state='running'], " <>
               "[data-last-run-state='retryable'], [data-last-run-state='verified'])"
           )
  end

  test "schedule and backup owners reject invalid fields independently", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/settings/schedules")

    # Earlier tests may have saved a different time; the rejected submit must keep whatever was stored.
    [stored_time] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("input[name='schedule[daily_time_wib]']")
      |> LazyHTML.attribute("value")

    view
    |> form("form[phx-submit='save_schedule']", %{
      "schedule" => %{"daily_time_wib" => "99:99", "enabled" => "true"}
    })
    |> render_submit()

    assert has_element?(view, "#settings-error", "Enter a valid WIB time.")

    view
    |> form("form[phx-submit='save_backup']", %{
      "backup" => %{"destination_directory" => "relative/backup"}
    })
    |> render_submit()

    assert has_element?(view, "#settings-error", "could not be saved safely")
    assert has_element?(view, "input[name='schedule[daily_time_wib]'][value='#{stored_time}']")
  end

  test "non-admin route denial happens before either settings surface renders", %{conn: conn} do
    {child_conn, _identity} =
      scenario_authenticated_conn(conn, "admin-settings-denial", ["children"])

    assert child_conn |> get("/admin/settings") |> response(404)
    assert child_conn |> get("/admin/settings/schedules") |> response(404)
  end

  describe "integrity label" do
    setup do
      location = TestBackupDestination.configure!("label")
      %{backup_directory: location.directory, backup_location: location}
    end

    test "a connected page states that every retained backup is present",
         %{conn: conn} = context do
      _context = BackupIntegrity.prepare(context, :label_destination, ["all_present"])

      {:ok, view, first} = live(conn, @route)
      assert label!(first).summary == @checking

      settled = render_async(view, IntegrityLabel.settle_ms())
      label = label!(settled)

      assert label.summary == "all 7 retained backups are present"
      assert label.problems == []
    end

    test "a connected page names each missing and changed date by its state",
         %{conn: conn} = context do
      context = BackupIntegrity.prepare(context, :label_destination, ["missing_and_changed"])

      {:ok, view, _first} = live(conn, @route)
      label = label!(render_async(view, IntegrityLabel.settle_ms()))

      assert label.summary == "2 of 7 retained backups need attention"
      assert label.problems == ["2030-05-12: file missing", "2030-05-14: file changed"]
      assert label.problems == BackupIntegrity.expected_label(context).problems
    end

    test "a reconciliation that raises reads as could not be checked beside a usable page",
         %{conn: conn} = context do
      _context = BackupIntegrity.prepare(context, :label_destination, ["raising"])

      {:ok, view, _first} = live(conn, @route)
      settled = render_async(view, IntegrityLabel.settle_ms())
      label = label!(settled)
      page = LazyHTML.from_fragment(settled)

      assert label.summary == @could_not_check
      assert label.problems == []
      assert_names_no_command(label)
      assert IntegrityLabel.forms_usable?(page)
      assert page |> LazyHTML.query("h1") |> LazyHTML.text() == "Schedules & backups"
    end

    test "a ledger holding no verified run reads as nothing to check yet",
         %{conn: conn} = context do
      _context = BackupIntegrity.prepare(context, :empty_ledger, [])

      {:ok, view, _first} = live(conn, @route)
      label = label!(render_async(view, IntegrityLabel.settle_ms()))

      assert label.summary == @nothing_to_check
      assert label.problems == []
    end

    test "the disconnected render states checking and opens neither ledger nor destination",
         %{conn: conn} = context do
      _context = BackupIntegrity.prepare(context, :label_destination, ["missing"])

      {html, events} =
        CallTrace.record(@check_calls, fn -> conn |> get(@route) |> html_response(200) end)

      assert label!(html).summary == @checking
      assert events == []
    end

    test "rendering and reloading leave the destination and the ledger unchanged",
         %{conn: conn} = context do
      context = BackupIntegrity.prepare(context, :label_destination, ["missing_and_unknown"])
      destination = BackupIntegrity.snapshot(context.backup_directory)
      ledger = BackupIntegrity.ledger_rows()

      _disconnected = conn |> get(@route) |> html_response(200)

      for _visit <- [:render, :reload] do
        {:ok, view, _first} = live(conn, @route)
        # The check ran (it names the missing artifact), so "unchanged" is a measured result.
        assert label!(render_async(view, IntegrityLabel.settle_ms())).problems ==
                 ["2030-05-12: file missing"]
      end

      assert BackupIntegrity.snapshot(context.backup_directory) == destination
      assert BackupIntegrity.ledger_rows() == ledger
    end

    test "the rendered label and page carry no path, digest, destination identifier or run ID",
         %{conn: conn} = context do
      context = BackupIntegrity.prepare(context, :label_destination, ["missing_and_changed"])

      {:ok, view, _first} = live(conn, @route)
      settled = render_async(view, IntegrityLabel.settle_ms())
      label = label!(settled)

      assert label.problems != []
      refute BackupIntegrity.leaks_private_value?(context, label.html)

      # The page's own folder field shows the configured folder; nothing else of the
      # destination or the ledger is on the page.
      private =
        [context.backup_location.destination_id] ++
          Enum.flat_map(context.ledger_runs, &[&1.run_id, &1.basename, &1.sha256])

      for value <- private, do: refute(settled =~ value)
    end

    test "the label is a polite region in its place, with a marker and no control",
         %{conn: conn} = context do
      _context = BackupIntegrity.prepare(context, :label_destination, ["missing_and_changed"])

      {:ok, view, first} = live(conn, @route)
      settled = render_async(view, IntegrityLabel.settle_ms())
      item = LazyHTML.from_fragment(label!(settled).html)

      pages = %{
        label_first: LazyHTML.from_fragment(first),
        label_page: LazyHTML.from_fragment(settled)
      }

      assert IntegrityLabel.outcome?(pages, :label_announced_in_place, [])
      assert IntegrityLabel.outcome?(pages, :result_announced_politely, [])
      assert IntegrityLabel.outcome?(pages, :focus_order_unchanged, [])
      assert Enum.count(LazyHTML.query(item, "[aria-live=polite]")) == 1
      assert Enum.empty?(LazyHTML.query(item, "[role=alert], [aria-live=assertive]"))
      assert Enum.count(LazyHTML.query(item, "svg[aria-hidden=true]")) == 1

      assert Enum.empty?(LazyHTML.query(item, "a, button, input, select, textarea, [tabindex]"))
    end

    test "a non-administrator gets not found and no reconciliation starts",
         %{conn: conn} = context do
      _context = BackupIntegrity.prepare(context, :label_destination, ["watched"])

      {child_conn, _identity} =
        scenario_authenticated_conn(Phoenix.ConnTest.build_conn(), "admin-settings-label", [
          "children"
        ])

      reads = ObservedArtifactStore.read_count()

      {_response, events} =
        CallTrace.record(@check_calls, fn -> assert child_conn |> get(@route) |> response(404) end)

      assert events == []
      assert ObservedArtifactStore.read_count() == reads

      # The same probe sees an administrator's visit, so the empty count above is a measurement.
      {:ok, view, _first} = live(conn, @route)
      _settled = render_async(view, IntegrityLabel.settle_ms())
      assert ObservedArtifactStore.read_count() > reads
    end
  end

  describe "integrity label ceiling" do
    setup do
      location = TestBackupDestination.configure!("label-ceiling")
      %{backup_directory: location.directory, backup_location: location}
    end

    test "a check that outlasts the ceiling reads as could not be checked and is cancelled",
         %{conn: conn} = context do
      context = BackupIntegrity.prepare(context, :label_destination, ["all_present"])
      newest = Enum.max_by(context.ledger_runs, & &1.date, Date)
      held = Path.join(context.backup_directory, newest.basename)

      # The read of the newest artifact never returns, so only the ceiling can end the check.
      :ok = ObservedArtifactStore.install!(block: held)
      :ok = IntegrityLabel.lower_ceiling!(@ceiling_ms)

      started = IntegrityLabel.now()
      {:ok, view, first} = live(conn, @route)

      # The page and both forms render first, and the label reads checking while the read is held.
      assert label!(first).summary == @checking
      assert IntegrityLabel.forms_usable?(LazyHTML.from_fragment(first))
      assert label!(render(view)).summary == @checking

      settled = await_result(view, @ceiling_ms + 2_000)
      elapsed = IntegrityLabel.now() - started

      assert label!(settled).summary == @could_not_check
      assert label!(settled).problems == []
      assert_names_no_command(label!(settled))
      assert elapsed >= @ceiling_ms
      assert IntegrityLabel.forms_usable?(LazyHTML.from_fragment(settled))

      # The work is cancelled, not left running: the process that was reading is dead shortly
      # after the ceiling and nothing reads the destination afterwards.
      observed = IntegrityLabel.observe_ceiling(elapsed)
      assert observed.blocked_pids != []
      assert observed.all_down?, "the process reading the destination outlived the ceiling"
      assert observed.reads_later == observed.reads_when_cancelled
    end
  end

  describe "integrity label re-check" do
    setup do
      location = TestBackupDestination.configure!("label-recheck")
      %{backup_directory: location.directory, backup_location: location}
    end

    test "a successful schedule save checks again and shows the new result",
         %{conn: conn} = context do
      context = BackupIntegrity.prepare(context, :label_destination, ["all_present"])
      {:ok, view, _first} = live(conn, @route)
      assert label!(render_async(view, IntegrityLabel.settle_ms())).summary == @all_present

      _context = BackupIntegrity.prepare(context, :expected_artifact_removed, [])
      after_save = view |> form("form[phx-submit=save_schedule]") |> render_submit()
      assert after_save =~ "Daily schedule saved."
      assert label!(after_save).summary == @checking

      settled = render_async(view, IntegrityLabel.settle_ms())
      label = label!(settled)
      assert label.summary == "1 of 7 retained backups needs attention"
      assert label.problems == ["2030-05-12: file missing"]
      refute_pushed_event()

      pages = %{
        label_after_save: LazyHTML.from_fragment(after_save),
        label_settled_after_save: LazyHTML.from_fragment(settled)
      }

      assert IntegrityLabel.outcome?(pages, :focus_does_not_move, [])
    end

    test "a successful backup folder save, the folder unchanged, checks again",
         %{conn: conn} = context do
      context = BackupIntegrity.prepare(context, :label_destination, ["all_present"])
      {:ok, view, _first} = live(conn, @route)
      assert label!(render_async(view, IntegrityLabel.settle_ms())).summary == @all_present

      _context = BackupIntegrity.prepare(context, :expected_artifact_removed, [])

      # The save queues the folder's first verification, which logs its own findings.
      {after_save, log} =
        ExUnit.CaptureLog.with_log(fn ->
          after_save = view |> form("form[phx-submit=save_backup]") |> render_submit()
          await_scheduler_tasks()
          after_save
        end)

      assert log =~ "Backup files"
      assert after_save =~ "Backup folder saved"
      assert label!(after_save).summary == @checking

      label = label!(render_async(view, IntegrityLabel.settle_ms()))
      assert label.summary == "1 of 7 retained backups needs attention"
      assert label.problems == ["2030-05-12: file missing"]
      refute_pushed_event()
    end

    test "a failed save starts no check", %{conn: conn} = context do
      _context = BackupIntegrity.prepare(context, :label_destination, ["watched"])
      {:ok, view, _first} = live(conn, @route)
      assert label!(render_async(view, IntegrityLabel.settle_ms())).summary == @all_present
      reads = ObservedArtifactStore.read_count()

      invalid_time = %{"schedule" => %{"daily_time_wib" => "99:99", "enabled" => "true"}}
      relative_folder = %{"backup" => %{"destination_directory" => "relative/backup"}}

      failed_schedule =
        view |> form("form[phx-submit=save_schedule]", invalid_time) |> render_submit()

      assert failed_schedule =~ "Enter a valid WIB time."
      assert label!(failed_schedule).summary == @all_present

      failed_folder =
        view |> form("form[phx-submit=save_backup]", relative_folder) |> render_submit()

      assert failed_folder =~ "could not be saved safely"
      assert label!(failed_folder).summary == @all_present

      # Nothing was started: no read follows and the label never left its result.
      Process.sleep(300)
      assert ObservedArtifactStore.read_count() == reads
      assert label!(render(view)).summary == @all_present
    end

    test "a second save while the first check is in flight leaves only the newer result",
         %{conn: conn} = context do
      context = BackupIntegrity.prepare(context, :label_destination, ["all_present"])
      newest = Enum.max_by(context.ledger_runs, & &1.date, Date)

      :ok =
        ObservedArtifactStore.install!(
          block: Path.join(context.backup_directory, newest.basename)
        )

      :ok = IntegrityLabel.lower_ceiling!(@ceiling_ms)

      {:ok, view, _first} = live(conn, @route)
      [first_reader] = await_blocked_reader()

      # The first check is held mid-read; an artifact is then removed, reads are free again
      # and the administrator saves.
      _context = BackupIntegrity.prepare(context, :expected_artifact_removed, [])
      :ok = ObservedArtifactStore.unblock!()
      after_save = view |> form("form[phx-submit=save_schedule]") |> render_submit()
      assert label!(after_save).summary == @checking

      label = label!(await_result(view, 2_000))
      assert label.summary == "1 of 7 retained backups needs attention"
      assert label.problems == ["2030-05-12: file missing"]

      # The first check can no longer report: past the ceiling it would have met, its reader
      # is gone and the label still shows the newer result.
      Process.sleep(@ceiling_ms + 200)
      refute Process.alive?(first_reader)
      assert label!(render(view)).summary == "1 of 7 retained backups needs attention"
    end
  end

  # The label speaks to the reader of the page: no command of the host, in text or attribute.
  defp assert_names_no_command(label) do
    refute String.downcase(label.html) =~ ~r/mix|bnest\.backup/
  end

  # The label of the Production database backup row of `html`; the assertion names the absent
  # label, which is the behavioural reason a check of it fails before it exists.
  defp label!(html) do
    label = html |> LazyHTML.from_document() |> IntegrityLabel.read()
    assert label, "the Production database backup row carries no Backup files term"
    label
  end

  # The page once its label no longer reads checking, or after `timeout` milliseconds.
  defp await_result(view, timeout),
    do: await_result(view, IntegrityLabel.now() + timeout, render(view))

  defp await_result(view, deadline, html) do
    if label!(html).summary != @checking or IntegrityLabel.now() >= deadline do
      html
    else
      Process.sleep(25)
      await_result(view, deadline, render(view))
    end
  end

  # The process that is held inside the blocked read, once there is one.
  defp await_blocked_reader(attempts \\ 100) do
    case ObservedArtifactStore.blocked_pids() do
      [] when attempts > 0 ->
        Process.sleep(20)
        await_blocked_reader(attempts - 1)

      readers ->
        readers
    end
  end

  # Waits for every task the Scheduler runs, such as the first verification a folder save queues.
  defp await_scheduler_tasks do
    BnestApp.Scheduler.Tasks
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      reference = Process.monitor(pid)

      receive do
        {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
      after
        30_000 -> flunk("a queued scheduler task did not finish")
      end
    end)
  end

  # A client command is how a server moves focus; the page sends none.
  defp refute_pushed_event, do: refute_receive({_reference, {:push_event, _event, _payload}}, 50)

  defp canonical_temporary_root do
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    String.trim(resolved)
  end
end
