defmodule BnestApp.Behaviour.CentralizedDataSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step("the browser has recognized Bnest chat, Sifat Allah, and explicit theme sources", context,
    do: prepare(context, :recognized_browser_sources)
  )

  step("the user confirms the recognized imports", context,
    do: perform(context, :confirm_imports)
  )

  step("Bnest preserves an immutable envelope for each source", context,
    do: outcome(context, :immutable_envelopes)
  )

  step("Bnest reads each normalized user-owned record successfully", context,
    do: outcome(context, :normalized_records_read)
  )

  step("the browser has no explicit theme source", context,
    do: prepare(context, :absent_theme_source)
  )

  step("Bnest records the absent system theme outcome", context,
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

  step("a recognized import was interrupted after source preservation", context,
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

  step("Bnest persists future changes only on the server", context,
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

  defp prepare(context, state),
    do: context.behaviour_driver.prepare_behaviour(context, state, [])

  defp perform(context, action),
    do: context.behaviour_driver.perform_behaviour(context, action, [])

  defp outcome(context, expected) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, [])
    context
  end
end
