defmodule BnestApp.Behaviour.ScheduledBackupSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step("no backup override exists", context, do: prepare(context, :no_backup_override))

  step("an administrator opened schedules and backups", context,
    do: prepare(context, :admin_opened_schedules)
  )

  step("the administrator saved an enabled daily WIB schedule", context,
    do: prepare(context, :saved_daily_schedule)
  )

  step("the scheduler missed more than one daily slot", context,
    do: prepare(context, :multiple_missed_slots)
  )

  step("a production backup claim is accepted", context,
    do: prepare(context, :accepted_backup_claim)
  )

  step("two coordinators observe the same slot and an attempt may lose its lease", context,
    do: prepare(context, :overlapping_coordinators)
  )

  step("family and admin-system daily schedules are persisted", context,
    do: prepare(context, :contextual_schedules)
  )

  step("an unauthenticated revoked or non-admin visitor", context,
    do: prepare(context, :denied_settings_visitor)
  )

  step("verified owned pairs span more than seven WIB dates beside unknown files", context,
    do: prepare(context, :retention_fixture)
  )

  step("a second allowlisted family handler is persisted", context,
    do: prepare(context, :second_family_handler)
  )

  step("multiple domains declare typed admin settings panels", context,
    do: prepare(context, :typed_settings_panels)
  )

  step("schedules use never absolute and occurrence expiration policies", context,
    do: prepare(context, :expiry_policies)
  )

  step("the daily backup destination resolves", context,
    do: perform(context, :resolve_backup_destination)
  )

  step("the administrator saves a safe backup override", context,
    do: perform(context, :save_backup_override)
  )

  step("the scheduler restarts before the schedule is due", context,
    do: perform(context, :restart_scheduler)
  )

  step("startup reconciliation runs", context, do: perform(context, :reconcile_startup))
  step("the backup handler runs", context, do: perform(context, :run_backup_handler))
  step("both coordinators reconcile", context, do: perform(context, :reconcile_overlap))

  step("an administrator follows schedules and backups from home", context,
    do: perform(context, :open_schedules_from_home)
  )

  step("the visitor opens an admin settings route", context,
    do: perform(context, :open_admin_settings)
  )

  step("a new backup becomes verified", context, do: perform(context, :verify_new_backup))
  step("its daily slot becomes due", context, do: perform(context, :run_second_handler))

  step("an administrator opens admin settings from home", context,
    do: perform(context, :open_admin_settings_from_home)
  )

  step("the coordinator reconciles claims and retries", context,
    do: perform(context, :reconcile_expiry)
  )

  step("Bnest uses the ignored repository backup folder", context,
    do: outcome(context, :default_backup_folder)
  )

  step("the verified result exposes no private path", context,
    do: outcome(context, :no_private_path)
  )

  step("Bnest stores the private backup configuration atomically", context,
    do: outcome(context, :atomic_backup_config)
  )

  step("Bnest creates one idempotent setup claim for that destination", context,
    do: outcome(context, :one_setup_claim)
  )

  step("the schedule remains enabled in SQLite", context,
    do: outcome(context, :schedule_persisted)
  )

  step("the same future UTC slot remains due", context, do: outcome(context, :same_future_slot))

  step("only the latest eligible slot is claimed", context,
    do: outcome(context, :latest_slot_only)
  )

  step("the next run advances to the next future day", context,
    do: outcome(context, :next_future_day)
  )

  step("only configured authoritative SQLite is snapshotted with VACUUM INTO", context,
    do: outcome(context, :authoritative_vacuum)
  )

  step("the candidate passes independent integrity and logical proof", context,
    do: outcome(context, :independent_proof)
  )

  step("SQLite accepts one claim and backup tasks do not overlap", context,
    do: outcome(context, :single_nonoverlap_claim)
  )

  step("transient failure receives at most three persisted attempts", context,
    do: outcome(context, :bounded_attempts)
  )

  step("both contexts appear in separate groups with safe status", context,
    do: outcome(context, :context_groups)
  )

  step("the backup row links to its typed settings", context,
    do: outcome(context, :typed_backup_link)
  )

  step("Bnest returns not found before protected reads", context,
    do: outcome(context, :not_found_before_reads)
  )

  step("home exposes no admin settings entry", context,
    do: outcome(context, :no_admin_home_entry)
  )

  step("Bnest keeps one newest owned pair for each retained WIB date", context,
    do: outcome(context, :owned_retention)
  )

  step("Bnest preserves unknown files and every previous destination", context,
    do: outcome(context, :preserve_unowned)
  )

  step("the shared coordinator and supervisor execute it", context,
    do: outcome(context, :shared_execution)
  )

  step("the shared ledger and contextual inventory record it", context,
    do: outcome(context, :shared_inventory)
  )

  step("every declared panel is discoverable", context,
    do: outcome(context, :panels_discoverable)
  )

  step("each owner validates and saves only its allowlisted fields", context,
    do: outcome(context, :owner_allowlists)
  )

  step("expiry blocks only ineligible future claims", context,
    do: outcome(context, :expiry_blocks_future)
  )

  step("retries do not consume occurrences or suppress the final occurrence", context,
    do: outcome(context, :retry_occurrence_rules)
  )

  # Backup integrity: reconciliation of the ledger against the destination, the reconcile
  # task's report, the post-run reconciliation and retention's ownership.

  step(
    "an isolated ledger of {int} verified runs on consecutive WIB dates from {string}",
    %{args: [count, first_date]} = context,
    do: prepare(context, :integrity_ledger, [count, first_date])
  )

  step("the destination holds the artifact and receipt of every run", context,
    do: prepare(context, :destination_holds_every_run)
  )

  step("the artifact and receipt of {string} are absent", %{args: [date]} = context,
    do: prepare(context, :pair_absent, [date])
  )

  step(
    "the artifact of {string} has a different digest from the ledger",
    %{args: [date]} = context,
    do: prepare(context, :artifact_digest_differs, [date])
  )

  step(
    "the artifact and receipt of {string} are absent because retention removed them",
    %{args: [date]} = context,
    do: prepare(context, :pair_removed_by_retention, [date])
  )

  step(
    "the ledger holds an older verified run on {string} whose artifact and receipt are absent",
    %{args: [date]} = context,
    do: prepare(context, :older_run_without_files, [date])
  )

  step("an unknown file sits in the destination", context, do: prepare(context, :unknown_file))

  step("an isolated destination and a ledger that cannot be read", context,
    do: prepare(context, :unreadable_ledger)
  )

  step("an isolated destination and a ledger holding no verified backup run", context,
    do: prepare(context, :empty_ledger)
  )

  step(
    "a scheduled backup in an isolated destination whose post-run reconciliation raises",
    context,
    do: prepare(context, :raising_reconciliation)
  )

  step("a destination holding owned pairs for eight WIB dates", context,
    do: prepare(context, :owned_pairs_for_eight_dates)
  )

  step(
    "receipts bearing another destination identifier, unreceipted artifacts and a malformed receipt",
    context,
    do: prepare(context, :foreign_and_unowned_files)
  )

  step("the test environment", context, do: prepare(context, :test_environment))

  step("reconciliation runs", context, do: perform(context, :reconcile_ledger))
  step("the reconcile task runs", context, do: perform(context, :reconcile_task))

  step("the reconcile task's printed report and the post-run log line are read", context,
    do: perform(context, :read_report_and_log)
  )

  step("the scheduled run completes", context, do: perform(context, :complete_scheduled_run))
  step("retention runs", context, do: perform(context, :run_retention))

  step("a test resolves the repository's default backup directory", context,
    do: perform(context, :resolve_default_directory)
  )

  step(
    "it reports the run of {string} as missing with its artifact basename",
    %{args: [date]} = context,
    do: outcome(context, :run_reported_missing, [date])
  )

  step(
    "it reports the runs of {string} and {string} as present",
    %{args: dates} = context,
    do: outcome(context, :runs_reported_present, dates)
  )

  step("it reports the run of {string} as changed", %{args: [date]} = context,
    do: outcome(context, :run_reported_changed, [date])
  )

  step("it does not report the run of {string}", %{args: [date]} = context,
    do: outcome(context, :run_not_reported, [date])
  )

  step("it reports the {int} other runs as present", %{args: [count]} = context,
    do: outcome(context, :other_runs_present, [count])
  )

  step("it reports the newer run of {string} as present", %{args: [date]} = context,
    do: outcome(context, :newer_run_present, [date])
  )

  step("it does not report the older run of {string}", %{args: [date]} = context,
    do: outcome(context, :older_run_not_reported, [date])
  )

  step("the destination listing and every file's bytes are unchanged", context,
    do: outcome(context, :destination_unchanged)
  )

  step("the ledger rows are unchanged", context, do: outcome(context, :ledger_unchanged))

  step("the report's first line is {string}", %{args: [line]} = context,
    do: outcome(context, :report_first_line, [line])
  )

  step("the report has no problem line", context, do: outcome(context, :report_no_problem_line))

  step("the report's problem lines are {string} and {string}", %{args: lines} = context,
    do: outcome(context, :report_problem_lines, lines)
  )

  step("the report's only problem line is {string}", %{args: [line]} = context,
    do: outcome(context, :report_problem_lines, [line])
  )

  step(
    "neither contains a filesystem path, a digest, a destination identifier or a run ID",
    context,
    do: outcome(context, :report_and_log_private_free)
  )

  step("the run is recorded verified and its artifact and receipt exist", context,
    do: outcome(context, :run_verified_with_files)
  )

  step("one path-free error line states that reconciliation failed", context,
    do: outcome(context, :reconciliation_failure_logged)
  )

  step(
    "it exits 0 and prints the summary line stating that all retained backups are present",
    context,
    do: outcome(context, :exit_zero_all_present)
  )

  step("it prints no per-date line", context, do: outcome(context, :report_no_date_line))
  step("it starts no scheduler", context, do: outcome(context, :scheduler_not_started))
  step("it exits non-zero", context, do: outcome(context, :exit_nonzero))

  step("the report names the date {string} and the state file missing", %{args: [date]} = context,
    do: outcome(context, :report_names_problem, [date, "file missing"])
  )

  step("the report names the date {string} and the state file changed", %{args: [date]} = context,
    do: outcome(context, :report_names_problem, [date, "file changed"])
  )

  step("the report contains no path, digest, destination identifier or run ID", context,
    do: outcome(context, :report_private_free)
  )

  step("the report states a path-free reason", context,
    do: outcome(context, :report_path_free_reason)
  )

  step("it prints that there is no verified backup to check yet", context,
    do: outcome(context, :report_nothing_to_check)
  )

  step("it prints no date as present and does not state that backups are present", context,
    do: outcome(context, :report_nothing_present)
  )

  step("exactly the owned pairs outside the seven latest dates are removed", context,
    do: outcome(context, :owned_pairs_outside_window_removed)
  )

  step("every foreign receipt, unreceipted artifact and malformed receipt is untouched", context,
    do: outcome(context, :unowned_files_untouched)
  )

  step("no foreign receipt changes which owned run is kept for a date", context,
    do: outcome(context, :foreign_receipts_never_counted)
  )

  step("the operation fails closed before any file is created", context,
    do: outcome(context, :default_directory_fails_closed)
  )

  step("the listing of the default backup directory is unchanged", context,
    do: outcome(context, :default_directory_unchanged)
  )

  # Backup integrity: the restore drill task, what it restores, prints and refuses.

  step(
    "an isolated destination holding a synthetic artifact of 1 room, {int} messages and {int} push subscriptions with deliveries {string} and {string}",
    %{args: args} = context,
    do: prepare(context, :drill_artifact, args)
  )

  step("an isolated destination holding a synthetic artifact", context,
    do: prepare(context, :drill_artifact)
  )

  step("a restorable regular file sits outside the destination", context,
    do: prepare(context, :drill_outside_file)
  )

  step("a directory sits inside the destination", context, do: prepare(context, :drill_directory))

  step(
    "a symbolic link inside the destination points to a restorable file outside it",
    context,
    do: prepare(context, :drill_symlink)
  )

  step("the restore drill task is run against that artifact", context,
    do: perform(context, :restore_drill, ["artifact"])
  )

  step(
    "the restore drill task is run against the file outside the destination by its absolute path",
    context,
    do: perform(context, :restore_drill, ["outside_absolute"])
  )

  step(
    "the restore drill task is run against the file outside the destination by a relative path that climbs out of it",
    context,
    do: perform(context, :restore_drill, ["outside_relative"])
  )

  step("the restore drill task is run against that directory", context,
    do: perform(context, :restore_drill, ["directory"])
  )

  step("the restore drill task is run against that symbolic link", context,
    do: perform(context, :restore_drill, ["symlink"])
  )

  step("it exits 0 and its first line is {string}", %{args: [line]} = context,
    do: outcome(context, :drill_exit_zero_first_line, [line])
  )

  step("it prints the line {string}", %{args: [line]} = context,
    do: outcome(context, :drill_prints_line, [line])
  )

  step("its last line is {string}", %{args: [line]} = context,
    do: outcome(context, :drill_last_line, [line])
  )

  step("it prints only the line {string}", %{args: [line]} = context,
    do: outcome(context, :drill_only_line, [line])
  )

  step(
    "its output carries no message body, push credential, filesystem path or artifact name",
    context,
    do: outcome(context, :drill_output_private_free)
  )

  step("it restored the artifact once into a fresh root that no longer exists", context,
    do: outcome(context, :drill_restored_once_root_gone)
  )

  step("nothing is restored", context, do: outcome(context, :drill_nothing_restored))
  step("no restore root is created", context, do: outcome(context, :drill_no_root_created))

  step("the live database is not opened", context,
    do: outcome(context, :live_database_not_opened)
  )

  # Backup integrity: the Schedules page's `Backup files` label, read from the page the
  # administrator opens.

  step(
    "an administrator and an isolated destination holding the artifact of every expected verified run",
    context,
    do: prepare(context, :label_destination, ["all_present"])
  )

  step(
    "an isolated ledger holding one verified run whose artifact is absent and one whose bytes differ from the ledger",
    context,
    do: prepare(context, :label_destination, ["missing_and_changed"])
  )

  step("a reconciliation that raises or a ledger that cannot be read", context,
    do: prepare(context, :label_destination, ["raising"])
  )

  step("a ledger holding no verified backup run", context, do: prepare(context, :empty_ledger))

  step(
    "an administrator who opened Schedules & backups while the label stated that all retained backups are present",
    context,
    do: prepare(context, :label_opened_all_present)
  )

  step("an expected artifact is then removed from the isolated destination", context,
    do: prepare(context, :expected_artifact_removed)
  )

  step("an isolated destination with a missing artifact and an unknown file", context,
    do: prepare(context, :label_destination, ["missing_and_unknown"])
  )

  step("reconciliation found a missing artifact", context,
    do: prepare(context, :label_destination, ["missing"])
  )

  step("a reconciliation that takes longer than the page's wait ceiling", context,
    do: prepare(context, :label_destination, ["ceiling"])
  )

  step("a visitor who is not an administrator", context,
    do: prepare(context, :label_denied_visitor)
  )

  step(
    "an isolated ledger holding two verified runs whose artifacts are absent or changed",
    context,
    do: prepare(context, :label_destination, ["two_problems"])
  )

  step("an administrator using only the keyboard and a screen reader", context,
    do: prepare(context, :label_destination, ["all_present"])
  )

  step("the administrator opens Schedules & backups", context,
    do: perform(context, :open_schedules_label)
  )

  step(
    "the administrator opens Schedules & backups at {int} x {int}",
    %{args: [width, height]} = context,
    do: perform(context, :open_schedules_label, [width, height])
  )

  step("the administrator saves the daily schedule", context,
    do: perform(context, :save_label_form, ["daily"])
  )

  step("the administrator saves the backup folder, left unchanged", context,
    do: perform(context, :save_label_form, ["backup_folder"])
  )

  step("the administrator opens the page and reloads it", context,
    do: perform(context, :open_and_reload_label)
  )

  step("the page's rendered text and attributes are read", context,
    do: perform(context, :read_label_and_report)
  )

  step("the administrator opens the page", context,
    do: perform(context, :open_label_past_ceiling)
  )

  step("the visitor opens the schedules route", context,
    do: perform(context, :open_schedules_route_denied)
  )

  step("the administrator moves through the page in reading order", context,
    do: perform(context, :open_schedules_label)
  )

  step(
    "the Production database backup section carries a backup-files label stating that all retained backups are present",
    context,
    do: outcome(context, :label_states_all_present)
  )

  step("the label lists no problem date", context, do: outcome(context, :label_no_problem_dates))

  step("the label states how many retained backups need attention", context,
    do: outcome(context, :label_counts_attention)
  )

  step("it lists each problem as its date and its state, missing or changed", context,
    do: outcome(context, :label_lists_problems)
  )

  step("the label lists the intact retained dates as present or counts them as present", context,
    do: outcome(context, :label_counts_intact_present)
  )

  step("the label states that the backup files could not be checked", context,
    do: outcome(context, :label_states_could_not_check)
  )

  step("the label asks the administrator to reload the page", context,
    do: outcome(context, :label_asks_reload)
  )

  step("the label names no command", context, do: outcome(context, :label_names_no_command))

  step("the rest of the page is rendered and its forms remain usable", context,
    do: outcome(context, :page_and_forms_usable)
  )

  step("the label states that there is no verified backup to check yet", context,
    do: outcome(context, :label_states_nothing_to_check)
  )

  step("it does not state that the backups are present", context,
    do: outcome(context, :label_not_present)
  )

  step("the label reads checking until the new result arrives", context,
    do: outcome(context, :label_checking_then_result)
  )

  step("it then states that one retained backup needs attention", context,
    do: outcome(context, :label_one_needs_attention)
  )

  step("the focus does not move", context, do: outcome(context, :focus_does_not_move))

  step("the destination directory listing and every file's bytes are unchanged", context,
    do: outcome(context, :rendered_destination_unchanged)
  )

  step("they contain no filesystem path, digest, destination identifier or run ID", context,
    do: outcome(context, :label_private_free)
  )

  step("they name the same dates and states as the reconcile task's report", context,
    do: outcome(context, :label_matches_report)
  )

  step("the page and its forms are rendered and usable before the result arrives", context,
    do: outcome(context, :forms_usable_before_result)
  )

  step("the label reads checking until the result or the ceiling", context,
    do: outcome(context, :label_checking_until_ceiling)
  )

  step("at the ceiling the label states that the backup files could not be checked", context,
    do: outcome(context, :label_could_not_check_at_ceiling)
  )

  step(
    "the check is cancelled at the ceiling and nothing keeps reading the destination afterwards",
    context,
    do: outcome(context, :check_cancelled_at_ceiling)
  )

  step("Bnest returns not found before any protected read", context,
    do: outcome(context, :not_found_before_reads)
  )

  step("no reconciliation is started", context, do: outcome(context, :no_reconciliation_started))

  step("the page does not scroll horizontally", context, do: outcome(context, :label_reflows))

  step("each problem line is fully visible, wrapped rather than truncated", context,
    do: outcome(context, :problem_lines_whole)
  )

  step("each problem is conveyed by text, not by colour alone", context,
    do: outcome(context, :problems_conveyed_by_text)
  )

  step(
    "the label is announced with its name and its state in its place before the forms",
    context,
    do: outcome(context, :label_announced_in_place)
  )

  step("the focus order of the existing controls is unchanged", context,
    do: outcome(context, :focus_order_unchanged)
  )

  step(
    "the change from checking to the result is announced politely and does not move focus",
    context,
    do: outcome(context, :result_announced_politely)
  )

  defp prepare(context, state, args \\ []),
    do: context.behaviour_driver.prepare_behaviour(context, state, args)

  defp perform(context, action, args \\ []),
    do: context.behaviour_driver.perform_behaviour(context, action, args)

  defp outcome(context, expected, args \\ []) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, args)
    context
  end
end
