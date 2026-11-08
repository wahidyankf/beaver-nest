# Bnest keeps browser import sources as flat files in its records store, which a SQLite-primary instance leaves in the
# data-free run base, so every scenario runs on a flat-primary test instance (ADR 001, sections 1 and 2).
@flat-primary
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
