Feature: Bnest authentication

  Scenario Outline: A logged-out visitor is sent to login from any protected page
    Given a visitor has no authenticated Bnest session
    When the visitor opens the protected route "<route>"
    Then Bnest redirects the visitor to login
    And the login form replaces protected home actions
    And the visitor sees no user data

    Examples:
      | route |
      | /chat |
      | /     |

  @flat-primary @open-setup
  Scenario: First-time setup warns that accounts cannot be managed or recovered later, then closes
    Given Bnest has not been set up yet
    When the maintainer submits all initial accounts including an administrator
    Then Bnest warns that later account management and password recovery are unavailable
    And setup and public registration are unavailable afterward

  Scenario: Approved user logs in and logs out
    Given an approved user account exists
    When the user logs in with valid credentials
    Then the protected home page is available
    When the user logs out from that browser
    Then that browser must log in again
