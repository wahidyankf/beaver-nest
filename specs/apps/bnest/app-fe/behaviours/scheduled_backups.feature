# These scenarios use Backup's default destination, so each instance's backup repository is a git repository (ADR 001,
# section 3).
@backup-repository
Feature: Bnest scheduled backups

  Background:
    Given an approved user is logged in

  Scenario: Show contextual daily schedules
    Given family and admin-system daily schedules are persisted
    When an administrator follows schedules and backups from home
    Then both contexts appear in separate groups with safe status
    And the backup row links to its typed settings

  Scenario Outline: A visitor who may not administer Bnest cannot open admin settings
    Given an unauthenticated revoked or non-admin visitor
    When the visitor opens the route "<route>"
    Then Bnest returns not found before protected reads
    And home exposes no admin settings entry
    And Bnest reveals no host path or migration inventory

    Examples:
      | route                     |
      | /admin/settings           |
      | /admin/settings/schedules |
      | /storage                  |

  Scenario: Every settings panel Bnest offers is listed in admin settings
    Given several areas of Bnest offer admin settings panels
    When an administrator opens admin settings from home
    Then every settings panel is listed in admin settings

  Scenario: A settings panel saves only the fields it offers and refuses any other field
    Given several areas of Bnest offer admin settings panels
    When an administrator opens admin settings from home
    Then each settings panel saves only the fields it offers and refuses any other field

  Scenario: The page states that every retained backup is present
    Given an administrator and an isolated destination holding the artifact of every expected verified run
    When the administrator opens Schedules & backups
    Then the Production database backup section carries a backup-files label stating that all retained backups are present
    And the label lists no problem date

  Scenario: The page names each date whose backup is missing or changed
    Given an isolated ledger holding one verified run whose artifact is absent and one whose bytes differ from the ledger
    When the administrator opens Schedules & backups
    Then the label states how many retained backups need attention
    And it lists each problem as its date and its state, missing or changed
    And the label lists the intact retained dates as present or counts them as present

  # Exemption(e2e): a forced reconciliation failure or an unreadable ledger cannot be produced from a browser against a healthy routed backend; alternative-proof: bnest-app:test:integration / The page says plainly when the check could not run
  @e2e-exempt
  Scenario: The page says plainly when the check could not run
    Given a reconciliation that raises or a ledger that cannot be read
    When the administrator opens Schedules & backups
    Then the label states that the backup files could not be checked
    And the label asks the administrator to reload the page
    And the label names no command
    And the rest of the page is rendered and its forms remain usable

  Scenario: The page says plainly when there is nothing to check
    Given a ledger holding no verified backup run
    When the administrator opens Schedules & backups
    Then the label states that there is no verified backup to check yet
    And it does not state that the backups are present

  Scenario Outline: The page checks again after the administrator saves
    Given an administrator who opened Schedules & backups while the label stated that all retained backups are present
    And an expected artifact is then removed from the isolated destination
    When the administrator saves the <form>
    Then the label reads checking until the new result arrives
    And it then states that one retained backup needs attention
    And the focus does not move

    Examples:
      | form                          |
      | daily schedule                |
      | backup folder, left unchanged |

  Scenario: Opening the page leaves the backup folder untouched
    Given an isolated destination with a missing artifact and an unknown file
    When the administrator opens the page and reloads it
    Then the destination directory listing and every file's bytes are unchanged

  Scenario: The label discloses no private path
    Given reconciliation found a missing artifact
    When the page's rendered text and attributes are read
    Then they contain no filesystem path, digest, destination identifier or run ID

  Scenario: The label names the same dates and states as the reconcile report
    Given reconciliation found a missing artifact
    When the page's rendered text and attributes are read
    Then they name the same dates and states as the reconcile task's report

  # Exemption(e2e): a reconciliation that outlasts the ceiling and its cancellation (a monitored process exit and no further read) need a controlled store whose reads outlast the ceiling and process monitoring the browser cannot reach; alternative-proof: bnest-app:test:integration / The label does not delay the page
  @e2e-exempt
  Scenario: The label does not delay the page
    Given a reconciliation that takes longer than the page's wait ceiling
    When the administrator opens the page
    Then the page and its forms are rendered and usable before the result arrives
    And the label reads checking until the result or the ceiling
    And at the ceiling the label states that the backup files could not be checked
    And the label asks the administrator to reload the page
    And the label names no command
    And the check is cancelled at the ceiling and nothing keeps reading the destination afterwards

  Scenario Outline: No horizontal scrolling and no hidden problem appears at any supported width
    Given an isolated ledger holding two verified runs whose artifacts are absent or changed
    When the administrator opens Schedules & backups at <viewport>
    Then the page does not scroll horizontally
    And each problem line is fully visible, wrapped rather than truncated
    And each problem is conveyed by text, not by colour alone

    Examples:
      | viewport   |
      | 320 x 568  |
      | 393 x 851  |
      | 768 x 1024 |
      | 1440 x 900 |

  Scenario: The label is reachable and announced without a pointer
    Given an administrator using only the keyboard and a screen reader
    When the administrator moves through the page in reading order
    Then the label is announced with its name and its state in its place before the forms
    And the focus order of the existing controls is unchanged
    And the change from checking to the result is announced politely and does not move focus

  # Carries BN-ADMIN-04.
  # Exemption(e2e): reach: the form's `type="time" required` input yields only a valid `HH:MM` or is blocked by the browser, so a malformed value cannot be submitted from a real browser; alternative-proof: bnest-app:test:integration / A bad schedule time says "Enter a valid WIB time."
  @e2e-exempt
  Scenario: A bad schedule time says "Enter a valid WIB time."
    Given an administrator with a saved daily schedule opens Schedules & backups
    When the administrator saves the daily schedule with the time "25:00"
    Then the schedules page shows the schedule error "Enter a valid WIB time."
    And the saved daily schedule keeps its time
    And the schedules page shows no schedule success message

  # Carries BN-ADMIN-05.
  Scenario: A stale schedule save says to reload and try again
    Given an administrator with a saved daily schedule opens Schedules & backups
    When another schedule save moves the daily schedule to "04:00"
    And the administrator saves the daily schedule with the time "03:00"
    Then the schedules page shows the schedule error "The schedule changed. Reload and try again."
    And the other schedule save stays

  # Carries BN-ADMIN-06.
  Scenario Outline: A bad backup folder gets a plain refusal reason
    Given an administrator opens Schedules & backups
    When the administrator saves the backup folder "<folder>"
    Then the schedules page shows the backup error "<message>"
    And nothing is saved and no first backup is queued

    Examples:
      | folder                          | message                                             |
      | inside the live database location | Choose a folder outside the live database location. |
      | a symbolic link                 | Choose a folder that is not a symbolic link.        |
      | a relative path                 | The backup folder could not be saved safely.        |
