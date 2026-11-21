Feature: Bnest authentication

  # Only a flat-primary instance with no seeded account keeps /setup open (ADR 001, section 2).
  @flat-primary @open-setup
  Scenario: Initial setup rejects a password missing a letter, number, or punctuation mark and accepts any length
    Given Bnest has not been set up yet
    When the maintainer submits all initial accounts including an administrator
    Then Bnest accepts the passwords without a character-count rule
    And Bnest rejects a password missing a letter, number, or punctuation mark

  # Only a flat-primary instance with no seeded account keeps /setup open (ADR 001, section 2).
  @flat-primary @open-setup
  Scenario: Initial setup creates the accounts once and then closes
    Given Bnest has not been set up yet
    When the maintainer submits all initial accounts including an administrator
    Then Bnest creates the accounts exactly once
    And setup and public registration are unavailable afterward

  Scenario: Logging in never exposes the password in storage, logs, or pages
    Given an approved user account exists
    When the user logs in with valid credentials
    Then no plaintext password is stored, logged, or rendered

  Scenario: Login persists across reload and browser restart until logout or browser data clearing
    Given an approved user is logged in
    When the user reloads and reopens Bnest in the same browser
    Then the same browser remains authenticated

  Scenario: One user can use independent simultaneous browser sessions
    Given one approved user is logged in on browser A and browser B
    When the user logs out from browser A
    Then browser A must log in again
    And browser B remains authenticated

  Scenario: A multi-role user receives only approved capabilities
    Given an approved user has the roles "parents" and "admin"
    When Bnest authorizes that user's own data operation
    Then the operation is allowed
    And an out-of-scope administration operation is denied

  Scenario: One authenticated user cannot change another user's data
    Given two approved users own separate Bnest data
    When the first user attempts the second user's data operation
    Then Bnest keeps the second user's data unchanged
