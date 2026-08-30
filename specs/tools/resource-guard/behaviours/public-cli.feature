Feature: Public resource guard CLI
  The repository can inspect and invoke the guard before Node or Nx starts.

  Scenario: JSON status exposes the stable evidence schema
    Given the compiled resource guard binary
    When JSON status is requested for an existing path
    Then status returns schema version 2 and a resource assessment

  Scenario: Run validates its command boundary
    Given the compiled resource guard binary
    When run is requested without a command separator
    Then the command fails with a useful validation error

  Scenario: Release summary assessment accepts healthy evidence
    Given a healthy release summary file
    When release summary assessment is requested
    Then the release evidence is accepted
