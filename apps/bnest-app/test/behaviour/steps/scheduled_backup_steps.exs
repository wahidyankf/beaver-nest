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

  defp prepare(context, state), do: context.behaviour_driver.prepare_behaviour(context, state, [])

  defp perform(context, action),
    do: context.behaviour_driver.perform_behaviour(context, action, [])

  defp outcome(context, expected) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, [])
    context
  end
end
