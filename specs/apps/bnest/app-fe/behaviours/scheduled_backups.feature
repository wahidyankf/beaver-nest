Feature: Bnest scheduled backups

  Background:
    Given an approved user is logged in

  Scenario: Show contextual daily schedules
    Given family and admin-system daily schedules are persisted
    When an administrator follows schedules and backups from home
    Then both contexts appear in separate groups with safe status
    And the backup row links to its typed settings

  Scenario: Deny schedule and configuration access
    Given an unauthenticated revoked or non-admin visitor
    When the visitor opens an admin settings route
    Then Bnest returns not found before protected reads
    And home exposes no admin settings entry

  Scenario: Discover typed admin configuration
    Given multiple domains declare typed admin settings panels
    When an administrator opens admin settings from home
    Then every declared panel is discoverable
    And each owner validates and saves only its allowlisted fields
