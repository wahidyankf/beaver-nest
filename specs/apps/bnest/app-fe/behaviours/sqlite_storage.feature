Feature: Bnest SQLite storage

  Background:
    Given an approved user is logged in

  Scenario: Non-admin cannot configure storage
    Given a non-admin family member is logged in
    When the user opens the storage settings route
    Then Bnest denies the operation
    And Bnest reveals no host path or migration inventory

  # Exemption(integration): client-side LiveView auto-reconnect and DOM draft recovery run in the browser JS client and are not observable from Phoenix.LiveViewTest; alternative-proof: bnest-app-fe-e2e:test:e2e / Routed client reconnects across compatible SQLite rollout
  @integration-exempt
  Scenario: Routed client reconnects across compatible SQLite rollout
    Given the current Caddy route is healthy and a connected user has acknowledged state
    When a revision-compatible candidate is promoted
    Then the routed revision and SQLite readiness are proven
    And the LiveView reconnects without a manual refresh
    And the acknowledged state and unsent draft remain available
