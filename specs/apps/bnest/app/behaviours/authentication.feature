Feature: Bnest authentication

  Scenario: Unauthenticated visitor is redirected before protected Bnest access
    Given a visitor has no authenticated Bnest session
    When the visitor opens the protected route "/chat"
    Then Bnest redirects the visitor to login
    And Bnest does not read or write user data

  Scenario: Initial setup warns about unavailable account recovery, creates all initial accounts once, and closes registration
    Given Bnest has no bootstrap journal
    When the maintainer submits all initial accounts including an administrator
    Then Bnest warns that later account management and password recovery are unavailable
    And Bnest accepts the passwords without a character-count rule
    And Bnest rejects a password missing a letter, number, or punctuation mark
    And Bnest creates the accounts exactly once
    And setup and public registration are unavailable afterward

  Scenario: Approved user logs in and logs out
    Given an approved user account exists
    When the user logs in with valid credentials
    Then the protected home page is available
    When the user logs out from that browser
    Then that browser must log in again

  Scenario: Login verifies a salted password hash without retaining plaintext
    Given an approved user account exists with an Argon2id verifier
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

  Scenario: One authenticated user cannot read or write another user's data
    Given two approved users own separate Bnest data
    When the first user attempts the second user's data operation
    Then Bnest denies the operation before repository access
