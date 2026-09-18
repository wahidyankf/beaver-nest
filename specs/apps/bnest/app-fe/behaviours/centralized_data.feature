Feature: Centralized Bnest data

  Background:
    Given an approved user is logged in

  Scenario: Accepted browser import clears only the accepted browser key
    Given a recognized browser source and an unrelated browser key exist
    When Bnest accepts and reads back the normalized record
    Then Bnest clears only the accepted source key

  Scenario: Failed Codex-thread resume reports a fresh conversation
    Given centralized chat contains a transcript and an unavailable Codex thread
    When the authenticated user continues the chat
    Then Bnest reports a fresh Codex conversation
