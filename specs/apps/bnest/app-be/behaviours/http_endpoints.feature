Feature: Bnest HTTP endpoints

  The application's own HTTP boundary: liveness, theme preference writes,
  public static files, and the stock not found page.

  Rule: Liveness reports the release it serves

  # Carries BN-HTTP-01.
  Scenario Outline: Liveness reports its status, revision, and slot
    Given the release names revision "<revision>" and slot "<slot>"
    When a visitor fetches the liveness probe
    Then the probe answers live with revision "<reported>" from slot "<reported-slot>"
    And the revision header carries "<reported>"

    Examples:
      | revision      | slot    | reported    | reported-slot |
      | test-revision | blue    | test-revision | blue        |
      | (unset)       | (unset) | development | standalone    |

  Rule: A theme change is saved or refused as invalid

  # Carries BN-HTTP-10.
  Scenario Outline: A theme change is saved or refused as invalid
    Given a visitor signed in as the scenario's owner
    And the owner saved theme "<saved>"
    When the visitor saves theme "<theme>"
    Then the theme answer is <status> with body "<body>"
    And the stored theme is "<stored>"

    Examples:
      | saved  | theme   | status | body           | stored |
      | dark   | light   | 204    | (empty)        | light  |
      | (none) | dark    | 204    | (empty)        | dark   |
      | dark   | system  | 204    | (empty)        | system |
      | dark   | neon    | 422    | Invalid theme. | dark   |
      | dark   | (empty) | 422    | Invalid theme. | dark   |

  # Carries BN-HTTP-10.
  # Exemption(e2e): every seeded account has a valid role and the e2e server's SQLite store is healthy, so nothing at the exact origin yields a 403 or a rejected write; alternative-proof: bnest-app:test:integration / A theme change is refused for a user without write rights or when the store rejects it
  @e2e-exempt
  Scenario Outline: A theme change is refused for a user without write rights or when the store rejects it
    Given a visitor signed in with "<roles>" roles
    And the preference store "<store>"
    When the visitor saves theme "<theme>"
    Then the theme answer is <status> with body "<body>"
    And the stored theme is "<stored>"

    Examples:
      | roles   | store          | theme | status | body                            | stored |
      | (empty) | accepts writes | dark  | 403    | Forbidden                       | system |
      | unknown | accepts writes | dark  | 403    | Forbidden                       | system |
      | admin   | rejects writes | dark  | 409    | Theme preference was not changed. | system |

  Rule: Public files are served without signing in

  # Carries BN-HTTP-23.
  Scenario Outline: A public static file is served without signing in
    Given a visitor with no session
    When the visitor fetches "<path>"
    Then the file answers 200 with its own "<media>" content

    Examples:
      | path                  | media                     |
      | /robots.txt           | text/plain                |
      | /manifest.webmanifest | application/manifest+json |

  Rule: Unknown paths get the stock not found page

  # Carries BN-HTTP-24.
  Scenario Outline: An unknown path gets the stock not found page, as HTML or JSON
    Given a visitor asking for "<media>"
    When the visitor opens the unknown path
    Then the unknown path answers 404 as "<format>"
    And the not found detail is "<detail>"

    Examples:
      | media            | format | detail    |
      | text/html        | HTML   | Not Found |
      | application/json | JSON   | Not Found |
