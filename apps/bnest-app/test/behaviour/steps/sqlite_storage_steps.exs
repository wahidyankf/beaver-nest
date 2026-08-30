defmodule BnestApp.Behaviour.SqliteStorageSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step("Bnest has no storage configuration", context,
    do: prepare(context, :no_storage_configuration)
  )

  step("the storage UI has not been visited", context,
    do: prepare(context, :storage_ui_not_visited)
  )

  step("managed migration starts", context, do: perform(context, :start_managed_migration))

  step("Bnest keeps the storage pointer under the configuration home", context,
    do: outcome(context, :pointer_under_configuration_home)
  )

  step("Bnest uses the environment-specific data directory for SQLite", context,
    do: outcome(context, :sqlite_under_production_data)
  )

  step("migration does not require a browser confirmation", context,
    do: outcome(context, :no_browser_confirmation)
  )

  step("an authenticated user with the admin role opened storage settings", context,
    do: prepare(context, :admin_opened_storage_settings)
  )

  step("migration has not started", context, do: prepare(context, :migration_not_started))

  step("the administrator enters a writable private server-local folder", context,
    do: perform(context, :enter_valid_folder)
  )

  step("Bnest normalizes the folder and appends the fixed database filename", context,
    do: outcome(context, :folder_normalized_with_fixed_filename)
  )

  step("Bnest stores only the validated absolute location in private machine state", context,
    do: outcome(context, :validated_location_stored_privately)
  )

  step(
    "the folder is relative, symlinked, world-writable, inside the repository, or overlaps a migration source",
    context,
    do: perform(context, :enter_unsafe_folder)
  )

  step("Bnest explains the safe correction", context,
    do: outcome(context, :safe_correction_explained)
  )

  step("Bnest creates no database or storage configuration", context,
    do: outcome(context, :no_storage_created)
  )

  step("an empty isolated database", context, do: prepare(context, :empty_isolated_database))

  step("the committed migration set is applied twice", context,
    do: perform(context, :apply_migration_set_twice)
  )

  step("the schema version and indexes match the declared checksum", context,
    do: outcome(context, :schema_matches_checksum)
  )

  step("the second run makes no duplicate table, index, or migration record", context,
    do: outcome(context, :no_duplicate_schema_objects)
  )

  step("a flat-primary installation has no custom storage location", context,
    do: prepare(context, :flat_primary_default_location)
  )

  step("no incompatible release slot can write", context,
    do: prepare(context, :no_incompatible_writer)
  )

  step("managed storage migration runs without a UI visit", context,
    do: perform(context, :run_managed_storage_migration)
  )

  step("Bnest inventories records in deterministic path order", context,
    do: outcome(context, :deterministic_inventory)
  )

  step("Bnest writes the database under the resolved storage directory", context,
    do: outcome(context, :database_under_resolved_directory)
  )

  step("each accepted item has immutable source and target checksum evidence", context,
    do: outcome(context, :checksum_evidence_present)
  )

  step("normal repository reads return the same validated record", context,
    do: outcome(context, :normal_reads_match)
  )

  step("migration stopped after at least one accepted item", context,
    do: prepare(context, :migration_stopped_after_progress)
  )

  step("the administrator retries the same migration identifier", context,
    do: perform(context, :retry_same_migration)
  )

  step("accepted matching items are not rewritten or duplicated", context,
    do: outcome(context, :accepted_items_not_duplicated)
  )

  step("remaining items continue from their recorded outcomes", context,
    do: outcome(context, :remaining_items_continue)
  )

  step("schema, backfill, parity, integrity, and isolated restore checks pass", context,
    do: prepare(context, :all_verification_checks_pass)
  )

  step(
    "the managed migration commits the storage authority switch without UI confirmation",
    context,
    do: perform(context, :commit_authority_switch)
  )

  step("future reads use SQLite", context, do: outcome(context, :future_reads_use_sqlite))

  step("future writes remain compatible with the rollback reader", context,
    do: outcome(context, :writes_compatible_with_rollback)
  )

  step("verified flat-file identity sources are retired", context,
    do: perform(context, :retire_flat_identity_sources)
  )

  step("chat, learning, theme, login, and logout survive an application restart", context,
    do: outcome(context, :journeys_survive_restart)
  )

  step("a source is malformed, unsupported, or changes after inventory", context,
    do: prepare(context, :malformed_or_changed_source)
  )

  step("Bnest verifies migration", context, do: perform(context, :verify_migration))

  step("SQLite does not become authoritative", context,
    do: outcome(context, :sqlite_not_authoritative)
  )

  step("the source and current flat-primary service remain unchanged", context,
    do: outcome(context, :source_and_service_unchanged)
  )

  step("the administrator sees a value-free retry category", context,
    do: outcome(context, :value_free_retry_category)
  )

  step("a non-admin family member is logged in", context,
    do: prepare(context, :non_admin_family_member)
  )

  step("the user opens the storage settings route", context,
    do: perform(context, :open_storage_settings_route)
  )

  step("Bnest denies the operation", context, do: outcome(context, :storage_access_denied))

  step("Bnest reveals no host path or migration inventory", context,
    do: outcome(context, :no_host_path_or_inventory_revealed)
  )

  step("the current Caddy route is healthy and a connected user has acknowledged state", context,
    do: prepare(context, :healthy_route_with_acknowledged_state)
  )

  step("a revision-compatible candidate is promoted", context,
    do: perform(context, :promote_compatible_candidate)
  )

  step("the routed revision and SQLite readiness are proven", context,
    do: outcome(context, :routed_revision_and_readiness_proven)
  )

  step("the LiveView reconnects without a manual refresh", context,
    do: outcome(context, :liveview_reconnects_without_refresh)
  )

  step("the acknowledged state and unsent draft remain available", context,
    do: outcome(context, :acknowledged_state_and_draft_available)
  )

  step("authoritative SQLite still uses the legacy configuration directory", context,
    do: prepare(context, :legacy_authoritative_sqlite)
  )

  step("managed storage relocation runs", context, do: perform(context, :relocate_storage))

  step("the storage pointer resolves the production data directory atomically", context,
    do: outcome(context, :pointer_relocated_atomically)
  )

  step(
    "legacy SQLite files remain until the new database passes routed proof",
    context,
    do: outcome(context, :legacy_sqlite_retained_until_proof)
  )

  step("routed SQLite proof matches the authoritative database generation", context,
    do: prepare(context, :routed_storage_generation_proven)
  )

  step("managed legacy storage cleanup runs", context,
    do: perform(context, :retire_legacy_storage)
  )

  step("Bnest removes every verified flat-file source and legacy SQLite sidecar", context,
    do: outcome(context, :verified_legacy_sources_removed)
  )

  step("Bnest preserves storage configuration and tracked placeholders", context,
    do: outcome(context, :config_and_placeholders_preserved)
  )

  defp prepare(context, state), do: context.behaviour_driver.prepare_behaviour(context, state, [])

  defp perform(context, action),
    do: context.behaviour_driver.perform_behaviour(context, action, [])

  defp outcome(context, expected) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, [])
    context
  end
end
