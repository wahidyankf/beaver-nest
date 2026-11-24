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

  # Carries BN-DATA-01.
  Scenario: The migration page lists each recognized browser source
    Given this browser holds chat, learning, and absent theme sources plus an unknown key
    When a visitor opens "/data-migration"
    Then the migration page lists "Chat conversation" as "Ready to preserve"
    And the migration page lists "Sifat Allah progress" as "Ready to preserve"
    And the migration page lists "Theme preference" as "Uses system default"
    And the migration page lists no unknown source

  # Carries BN-DATA-09.
  Scenario Outline: Each import outcome shows its label and its status
    Given a browser source filed as "<filed>"
    When the user confirms the recognized imports
    Then the migration page shows "<label>: <status>"

    Examples:
      | filed    | label             | status                                   |
      | accepted | Chat conversation | accepted and verified                    |
      | rejected | Chat conversation | rejected safely; browser source retained |

  # Carries BN-DATA-09.
  # Exemption(e2e): reach: a retryable outcome needs a storage write failure and a stale-revision outcome needs a concurrent newer record, neither of which the browser can cause on a healthy single server; the accepted and rejected outcomes stay bound at e2e above; alternative-proof: bnest-app:test:integration / Each retryable or stale import outcome shows its label and its status
  @e2e-exempt
  Scenario Outline: Each retryable or stale import outcome shows its label and its status
    Given a browser source filed as "<filed>"
    When the user confirms the recognized imports
    Then the migration page shows "<label>: <status>"

    Examples:
      | filed     | label             | status                                          |
      | retryable | Chat conversation | not completed; retry without re-entering data   |
      | stale     | Chat conversation | newer server data exists; refresh before retrying |

  # Carries BN-DATA-10.
  Scenario: A browser acting as the local user is told to log in before importing
    Given identity cutover is off
    When the visitor opens the migration page on the cutover-off candidate
    Then the visitor lands on the home page with the login warning
    And the visitor sees no import control
