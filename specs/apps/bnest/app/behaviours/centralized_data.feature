Feature: Centralized Bnest data

  Background:
    Given an approved user is logged in

  Scenario: Authenticated user imports each recognized browser source
    Given the browser has recognized Bnest chat, Sifat Allah, and explicit theme sources
    When the user confirms the recognized imports
    Then Bnest preserves an immutable envelope for each source
    And Bnest reads each normalized user-owned record successfully

  Scenario: Absent system theme is recorded without creating a preference
    Given the browser has no explicit theme source
    When the user confirms the recognized imports
    Then Bnest records the absent system theme outcome
    And Bnest creates no explicit theme preference

  Scenario: Unknown, malformed, or oversized browser input is rejected without source deletion
    Given the browser has an invalid Bnest source
    When the user confirms the recognized imports
    Then Bnest reports a safe rejected import
    And the browser source and accepted server record remain unchanged

  Scenario: Retrying an interrupted import does not duplicate accepted data
    Given a recognized import was interrupted after source preservation
    When the user retries that import
    Then Bnest reuses its idempotent import identity
    And Bnest does not duplicate or overwrite accepted data

  Scenario: A stale browser cannot overwrite a newer centralized record
    Given browser B has an older revision than browser A
    When browser B writes the stale record
    Then Bnest keeps the newer centralized record
    And browser B is asked to refresh

  Scenario: Accepted browser import clears only Bnest persisted browser keys after server read-back
    Given a recognized browser source and an unrelated browser key exist
    When Bnest accepts and reads back the normalized record
    Then Bnest clears only the accepted source key
    And Bnest persists future changes only on the server

  Scenario: Failed Codex-thread resume preserves transcript and starts a reported fresh conversation
    Given centralized chat contains a transcript and an unavailable Codex thread
    When the authenticated user continues the chat
    Then Bnest preserves the transcript
    And Bnest reports a fresh Codex conversation
