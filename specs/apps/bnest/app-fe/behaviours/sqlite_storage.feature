Feature: Bnest SQLite storage

  Background:
    Given an approved user is logged in

  Scenario: Non-admin cannot configure storage
    Given a non-admin family member is logged in
    When the user opens the storage settings route
    Then Bnest denies the operation
    And Bnest reveals no host path or migration inventory

  # Exemption(integration): client-side LiveView auto-reconnect and DOM draft recovery run in the browser JS client and are not observable from Phoenix.LiveViewTest; alternative-proof: bnest-app-fe-e2e:test:e2e / A connected user keeps their state across a compatible release
  @integration-exempt
  Scenario: A connected user keeps their state across a compatible release
    Given the current site is healthy and a connected user has acknowledged state
    When a compatible new release is promoted
    Then the deploy report names the new release and shows SQLite ready
    And the LiveView reconnects without a manual refresh
    And the acknowledged state and unsent draft remain available
