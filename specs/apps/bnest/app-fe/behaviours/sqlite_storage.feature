Feature: Bnest SQLite storage

  Background:
    Given an approved user is logged in

  # Exemption(integration): client-side LiveView auto-reconnect and DOM draft recovery run in the browser JS client and are not observable from Phoenix.LiveViewTest; alternative-proof: bnest-app-fe-e2e:test:e2e / A connected user keeps their state across a compatible release
  @integration-exempt
  Scenario: A connected user keeps their state across a compatible release
    Given the current site is healthy and a connected user has acknowledged state
    When a compatible new release is promoted
    Then the deploy report names the new release and shows SQLite ready
    And the LiveView reconnects without a manual refresh
    And the acknowledged state and unsent draft remain available

  @flat-primary
  Scenario Outline: The storage status reads Not started, Blocked, or SQLite active
    Given a storage installation in "<setup>" state
    When the administrator opens /storage
    Then the page reads "Status: <status>"

    Examples:
      | setup              | status                    |
      | fresh flat-primary | Not started               |
      | blocked migration  | Blocked — retry available |
      | active SQLite      | SQLite active             |

  @flat-primary
  Scenario: Move data and Retry migration start or retry the migration
    Given a flat-primary installation with seeded family data and one malformed source
    Then the storage control reads "Move data"
    When the administrator presses "Move data"
    Then the page reads "Status: Blocked — retry available" and the control reads "Retry migration"
    When the operator repairs the malformed source and the administrator presses "Retry migration"
    Then the page reads "Status: SQLite active"

  @flat-primary
  Scenario: The folder is locked once migration has started
    Given a flat-primary installation with a migration in progress
    When the administrator opens /storage
    Then the folder input and the Check folder button are disabled and Create database is not offered
