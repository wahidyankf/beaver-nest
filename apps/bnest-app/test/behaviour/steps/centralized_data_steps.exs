defmodule BnestApp.Behaviour.CentralizedDataSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step("the browser has recognized Bnest chat, Sifat Allah, and explicit theme sources", context,
    do: prepare(context, :recognized_browser_sources)
  )

  step("the user confirms the recognized imports", context,
    do: perform(context, :confirm_imports)
  )

  step("Bnest reports each source as accepted and verified", context,
    do: outcome(context, :immutable_envelopes)
  )

  step("Bnest preserves an immutable envelope for each source", context,
    do: outcome(context, :immutable_envelopes)
  )

  step("the user's chat, Sifat Allah progress, and theme are read back from Bnest", context,
    do: outcome(context, :normalized_records_read)
  )

  step("the browser has no explicit theme source", context,
    do: prepare(context, :absent_theme_source)
  )

  step(
    "Bnest reports the theme import as accepted with nothing for the browser to clear",
    context,
    do: outcome(context, :absent_theme_recorded)
  )

  step("Bnest creates no explicit theme preference", context,
    do: outcome(context, :no_theme_preference)
  )

  step("the browser has an invalid Bnest source", context,
    do: prepare(context, :invalid_browser_source)
  )

  step("Bnest reports a safe rejected import", context,
    do: outcome(context, :safe_rejected_import)
  )

  step("the browser source and accepted server record remain unchanged", context,
    do: outcome(context, :source_and_record_unchanged)
  )

  step(
    "a recognized import was interrupted after source preservation and before its data was saved",
    context,
    do: prepare(context, :interrupted_import)
  )

  step("the user retries that import", context, do: perform(context, :retry_import))

  step("Bnest reuses its idempotent import identity", context,
    do: outcome(context, :idempotent_import_identity)
  )

  step("Bnest does not duplicate or overwrite accepted data", context,
    do: outcome(context, :accepted_data_preserved)
  )

  step("browser B has an older revision than browser A", context,
    do: prepare(context, :stale_browser_revision)
  )

  step("browser B writes the stale record", context, do: perform(context, :write_stale_record))

  step("Bnest keeps the newer centralized record", context,
    do: outcome(context, :newer_record_preserved)
  )

  step("browser B is asked to refresh", context, do: outcome(context, :refresh_required))

  step("a recognized browser source and an unrelated browser key exist", context,
    do: prepare(context, :recognized_and_unrelated_keys)
  )

  step("Bnest accepts and reads back the normalized record", context,
    do: perform(context, :accept_and_read_back)
  )

  step("Bnest clears only the accepted source key", context,
    do: outcome(context, :only_accepted_key_cleared)
  )

  step("the user confirms the recognized imports and then changes the theme", context,
    do: context |> perform(:accept_and_read_back) |> perform(:change_theme)
  )

  step("the change is saved on the server and the browser is told to keep no copy", context,
    do: outcome(context, :server_only_persistence)
  )

  step("centralized chat contains a transcript and an unavailable Codex thread", context,
    do: prepare(context, :unavailable_codex_thread)
  )

  step("the authenticated user continues the chat", context, do: perform(context, :continue_chat))

  step("Bnest preserves the transcript", context, do: outcome(context, :transcript_preserved))

  step("Bnest reports a fresh Codex conversation", context,
    do: outcome(context, :fresh_conversation_reported)
  )

  # BN-DATA-01, BN-DATA-09 and BN-DATA-10: the migration page's source list,
  # import outcomes and local-user login gate.

  step(
    "this browser holds chat, learning, and absent theme sources plus an unknown key",
    context,
    do: prepare(context, :migration_mixed_sources, [])
  )

  step("a browser source filed as {string}", %{args: [filed]} = context,
    do: prepare(context, :filed_browser_source, [filed])
  )

  step(
    "the visitor opens the migration page on the cutover-off candidate",
    context,
    do: perform(context, :open_migration_cutover_off, [])
  )

  step("the migration page lists {string} as {string}", %{args: [label, status]} = context,
    do: outcome(context, :migration_source_listed, [label, status])
  )

  step("the migration page lists no unknown source", context,
    do: outcome(context, :migration_no_unknown)
  )

  step("the migration page shows {string}", %{args: [line]} = context,
    do: outcome(context, :migration_outcome_shown, [line])
  )

  step("the visitor lands on the home page with the login warning", context,
    do: outcome(context, :migration_login_warning, [])
  )

  step("the visitor sees no import control", context,
    do: outcome(context, :migration_no_import_control, [])
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
