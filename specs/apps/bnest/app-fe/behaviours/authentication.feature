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

  # Carries BN-HTTP-05.
  Scenario Outline: A login return path stays on this site
    Given an approved user account exists
    When the user logs in with return path "<return_to>"
    Then the user lands on "<path>"

    Examples:
      | return_to          | path  |
      | /chat              | /chat |
      | //evil.example      | /     |
      | https://evil.example | /   |
      | chat               | /     |
      | (empty)            | /     |

  # Carries BN-HTTP-07 and BN-AUTH-03.
  Scenario: A wrong login stays on the login page and says it is not valid
    Given an approved user account exists
    When the user logs in with the wrong password
    Then the login page says the login is not valid
    And no identity cookie is set
    When an unknown user logs in
    Then the login page says the login is not valid
    And no identity cookie is set

  # Carries BN-AUTH-11.
  Scenario: With identity cutover off an unsigned browser acts as the local user
    Given identity cutover is off
    And a visitor has no authenticated Bnest session
    When the visitor opens this site's home page
    Then the visitor acts as the local browser user
    When identity cutover is on
    And the visitor opens this site's home page
    Then Bnest redirects the visitor to login

  # Carries BN-SETUP-01.
  # Exemption(integration): the cards are added by browser JavaScript that Phoenix.LiveViewTest never executes, and /setup markup alone shows only the first card; alternative-proof: bnest-app:test:unit / the vitest scenario and bnest-app-fe-e2e:test:e2e / The setup page adds and removes family member cards
  @open-setup @flat-primary @integration-exempt
  Scenario: The setup page adds and removes family member cards
    Given Bnest has not been set up yet
    When the setup page is shown
    Then it opens with one administrator card
    And the first card offers no remove control
    And it offers to add another initial account
    And the card template numbers a new family member card

  # Carries BN-SETUP-03, BN-SETUP-04 and BN-SETUP-06.
  @open-setup @flat-primary
  Scenario Outline: A setup submission that breaks a rule is refused and creates no account
    Given Bnest has not been set up yet
    When the maintainer submits the "<case>" setup
    Then setup stays open with "<message>"
    And no account is created

    Examples:
      | case               | message                                                  |
      | no admin           | At least one initial account must have the admin role.   |
      | duplicate username | Each username must be unique regardless of letter case.  |
      | empty username     | Use 1–32 letters, numbers, dots, dashes, or underscores. |
      | long username      | Use 1–32 letters, numbers, dots, dashes, or underscores. |
      | password mismatch  | Each password and confirmation must match.               |
      | unchecked box      | Confirm that setup closes permanently before continuing. |

  # Carries BN-SETUP-07.
  @open-setup @flat-primary
  Scenario: A failed setup keeps the names and roles and clears every password
    Given Bnest has not been set up yet
    When the maintainer submits two accounts with mismatched passwords
    Then the setup form keeps both usernames and ticked roles
    And every password field is empty
    And the refusal shows in an alert
