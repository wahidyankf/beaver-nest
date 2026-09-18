Feature: Bnest authentication

  Scenario: Unauthenticated visitor is redirected before protected Bnest access
    Given a visitor has no authenticated Bnest session
    When the visitor opens the protected route "/chat"
    Then Bnest redirects the visitor to login
    And Bnest does not read or write user data

  Scenario: Logged-out home presents login instead of protected actions
    Given a visitor has no authenticated Bnest session
    When the visitor opens the protected route "/"
    Then Bnest redirects the visitor to login
    And the login form replaces protected home actions
    And Bnest does not read or write user data

  Scenario: Initial setup warns about unavailable recovery and closes registration
    Given Bnest has no bootstrap journal
    When the maintainer submits all initial accounts including an administrator
    Then Bnest warns that later account management and password recovery are unavailable
    And setup and public registration are unavailable afterward

  Scenario: Approved user logs in and logs out
    Given an approved user account exists
    When the user logs in with valid credentials
    Then the protected home page is available
    When the user logs out from that browser
    Then that browser must log in again
