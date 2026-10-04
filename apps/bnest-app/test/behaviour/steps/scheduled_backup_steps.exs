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

  defp prepare(context, state, args \\ []),
    do: context.behaviour_driver.prepare_behaviour(context, state, args)

  defp perform(context, action, args \\ []),
    do: context.behaviour_driver.perform_behaviour(context, action, args)

  defp outcome(context, expected, args \\ []) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, args)
    context
  end
end
