# Bnest keeps browser import sources as flat files in its records store, which a SQLite-primary instance leaves in the
# data-free run base, so every scenario runs on a flat-primary test instance (ADR 001, sections 1 and 2).
@flat-primary
Feature: Centralized Bnest data

  Background:
    Given an approved user is logged in

  Scenario: Confirming the recognized browser imports reports each source accepted and serves the imported data back to the user
    Given the browser has recognized Bnest chat, Sifat Allah, and explicit theme sources
    When the user confirms the recognized imports
    Then Bnest reports each source as accepted and verified
    And Bnest preserves an immutable envelope for each source
    And the user's chat, Sifat Allah progress, and theme are read back from Bnest

  Scenario: Importing with no explicit browser theme leaves the theme at the system default
    Given the browser has no explicit theme source
    When the user confirms the recognized imports
    Then Bnest reports the theme import as accepted with nothing for the browser to clear
    And Bnest creates no explicit theme preference

  Scenario: Unknown, malformed, or oversized browser input is rejected without source deletion
    Given the browser has an invalid Bnest source
    When the user confirms the recognized imports
    Then Bnest reports a safe rejected import
    And the browser source and accepted server record remain unchanged

  # The interrupted-import seed is a flat-primary record kind (ADR 001, section 2).
  Scenario: Retrying an interrupted import completes it without duplicating data
    Given a recognized import was interrupted after source preservation and before its data was saved
    When the user retries that import
    Then Bnest reuses its idempotent import identity
    And Bnest does not duplicate or overwrite accepted data

  Scenario: A stale browser cannot overwrite a newer centralized record
    Given browser B has an older revision than browser A
    When browser B writes the stale record
    Then Bnest keeps the newer centralized record
    And browser B is asked to refresh

  Scenario: After an accepted import, later changes are kept on the server and the browser keeps no copy
    Given a recognized browser source and an unrelated browser key exist
    When the user confirms the recognized imports and then changes the theme
    Then the change is saved on the server and the browser is told to keep no copy

  Scenario: Failed Codex-thread resume preserves the transcript
    Given centralized chat contains a transcript and an unavailable Codex thread
    When the authenticated user continues the chat
    Then Bnest preserves the transcript
