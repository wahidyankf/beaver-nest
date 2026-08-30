import { createBdd } from "playwright-bdd";
import {
  expectScheduledBackup,
  performScheduledBackup,
  prepareScheduledBackup,
  type ScheduledBackupWorld,
} from "../support/scheduled-backups";

const { Given, Then, When } = createBdd();
const world: ScheduledBackupWorld = {};

const preparations = new Map<string, string>([
  ["no backup override exists", "no_backup_override"],
  ["an administrator opened schedules and backups", "admin_opened_schedules"],
  [
    "the administrator saved an enabled daily WIB schedule",
    "saved_daily_schedule",
  ],
  ["the scheduler missed more than one daily slot", "multiple_missed_slots"],
  ["a production backup claim is accepted", "accepted_backup_claim"],
  [
    "two coordinators observe the same slot and an attempt may lose its lease",
    "overlap",
  ],
  [
    "family and admin-system daily schedules are persisted",
    "contextual_schedules",
  ],
  ["an unauthenticated revoked or non-admin visitor", "denied_visitor"],
  [
    "verified owned pairs span more than seven WIB dates beside unknown files",
    "retention",
  ],
  ["a second allowlisted family handler is persisted", "second_handler"],
  ["multiple domains declare typed admin settings panels", "typed_panels"],
  ["schedules use never absolute and occurrence expiration policies", "expiry"],
]);

const actions = new Map<string, string>([
  ["the daily backup destination resolves", "resolve_backup_destination"],
  ["the administrator saves a safe backup override", "save_backup_override"],
  ["the scheduler restarts before the schedule is due", "restart_scheduler"],
  ["startup reconciliation runs", "reconcile_startup"],
  ["the backup handler runs", "run_backup_handler"],
  ["both coordinators reconcile", "reconcile_overlap"],
  [
    "an administrator follows schedules and backups from home",
    "open_schedules_from_home",
  ],
  ["the visitor opens an admin settings route", "open_admin_settings"],
  ["a new backup becomes verified", "verify_new_backup"],
  ["its daily slot becomes due", "run_second_handler"],
  [
    "an administrator opens admin settings from home",
    "open_admin_settings_from_home",
  ],
  ["the coordinator reconciles claims and retries", "reconcile_expiry"],
]);

const outcomes = new Map<string, string>([
  ["Bnest uses the ignored repository backup folder", "default_backup_folder"],
  ["the verified result exposes no private path", "no_private_path"],
  [
    "Bnest stores the private backup configuration atomically",
    "atomic_backup_config",
  ],
  [
    "Bnest creates one idempotent setup claim for that destination",
    "one_setup_claim",
  ],
  ["the schedule remains enabled in SQLite", "schedule_persisted"],
  ["the same future UTC slot remains due", "same_future_slot"],
  ["only the latest eligible slot is claimed", "latest_slot_only"],
  ["the next run advances to the next future day", "next_future_day"],
  [
    "only configured authoritative SQLite is snapshotted with VACUUM INTO",
    "vacuum",
  ],
  ["the candidate passes independent integrity and logical proof", "proof"],
  ["SQLite accepts one claim and backup tasks do not overlap", "single_claim"],
  ["transient failure receives at most three persisted attempts", "attempts"],
  ["both contexts appear in separate groups with safe status", "groups"],
  ["the backup row links to its typed settings", "typed_link"],
  ["Bnest returns not found before protected reads", "not_found"],
  ["home exposes no admin settings entry", "no_entry"],
  ["Bnest keeps one newest owned pair for each retained WIB date", "retention"],
  ["Bnest preserves unknown files and every previous destination", "preserve"],
  ["the shared coordinator and supervisor execute it", "shared_execution"],
  ["the shared ledger and contextual inventory record it", "shared_inventory"],
  ["every declared panel is discoverable", "panels"],
  ["each owner validates and saves only its allowlisted fields", "allowlists"],
  ["expiry blocks only ineligible future claims", "expiry"],
  [
    "retries do not consume occurrences or suppress the final occurrence",
    "occurrences",
  ],
]);

for (const [text, state] of preparations)
  Given(text, ({ $testInfo }) =>
    prepareScheduledBackup(world, state, $testInfo),
  );

for (const [text, action] of actions)
  When(text, ({ page }) => performScheduledBackup(page, world, action));

for (const [text, outcome] of outcomes)
  Then(text, ({ page }) => expectScheduledBackup(page, world, outcome));
