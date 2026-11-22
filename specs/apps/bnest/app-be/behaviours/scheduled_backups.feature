Feature: Bnest scheduled backups

  Background:
    Given an approved user is logged in

  Scenario: A daily backup with no saved folder is written to the repository backup folder
    Given no backup override exists
    When the daily backup runs
    Then the backup and its receipt appear in the ignored repository folder and the receipt holds no private path

  Scenario: Saving a backup folder confirms the save and queues one first check, however often it is submitted
    Given an administrator opened schedules and backups
    When the administrator saves a safe backup override
    Then the page shows the saved confirmation, shows the folder when reopened, and one first verification runs for a double submit

  # Exemption(e2e): the browser and HTTP client cannot restart the Bnest server process, which the When needs; alternative-proof: bnest-app:test:integration / A saved daily schedule survives a restart
  @e2e-exempt
  Scenario: A saved daily schedule survives a restart
    Given the administrator saved an enabled daily WIB schedule
    When the scheduler restarts before the schedule is due
    Then the schedules page shows the schedule enabled with the same next run time after Bnest restarts

  # Exemption(e2e): the browser and HTTP client cannot stop the Bnest server across missed daily slots and start it again; alternative-proof: bnest-app:test:integration / After downtime only one catch-up backup runs
  @e2e-exempt
  Scenario: After downtime only one catch-up backup runs
    Given the scheduler missed more than one daily slot
    When Bnest starts after missing several daily backups
    Then exactly one backup run is recorded and the next run shows tomorrow's time

  # Exemption(e2e): the scheduled backup handler runs inside the Bnest server on a daily claim, which a browser and HTTP client cannot start; alternative-proof: bnest-app:test:integration / A scheduled backup produces a verified snapshot of the live database
  @e2e-exempt
  Scenario: A scheduled backup produces a verified snapshot of the live database
    Given a production backup claim is accepted
    When the backup handler runs
    Then a backup file with its receipt appears and the run shows verified

  Rule: The reconcile task checks only the retained backups and changes no file

    # Exemption(e2e): the browser and HTTP client cannot seed an eight-night ledger in the server's run store, which the Given needs; alternative-proof: bnest-app:test:integration / The reconcile task ignores a backup older than the seven retained days
    @e2e-exempt
    Scenario: The reconcile task ignores a backup older than the seven retained days
      Given an isolated ledger of 8 verified runs on consecutive WIB dates from "2030-05-11"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-11" are absent because retention removed them
      When the reconcile task runs
      Then it exits 0 and says all 7 retained backups are present

    # Exemption(e2e): the browser and HTTP client cannot write a second verified run for one WIB date into the server's run store; alternative-proof: bnest-app:test:integration / The reconcile task expects only the newest backup of each day
    @e2e-exempt
    Scenario: The reconcile task expects only the newest backup of each day
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the ledger holds an older verified run on "2030-05-15" whose artifact and receipt are absent
      When the reconcile task runs
      Then it exits 0 and does not flag the older backup of "2030-05-15" whose files are gone

    # Exemption(e2e): the browser and HTTP client cannot read the destination's file bytes before and after the Mix task runs; alternative-proof: bnest-app:test:integration / The reconcile task changes no backup file
    @e2e-exempt
    Scenario: The reconcile task changes no backup file
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-16" are absent
      And an unknown file sits in the destination
      When the reconcile task runs
      Then the destination listing and every file's bytes are unchanged

  Rule: The reconcile report states each result in one fixed wording

    # Exemption(e2e): the browser and HTTP client cannot run the reconcile Mix task or read the lines it prints; alternative-proof: bnest-app:test:integration / The report counts the backups that need attention
    @e2e-exempt
    Scenario Outline: The report counts the backups that need attention
      Given an isolated ledger of 7 verified runs on consecutive WIB dates from "2030-05-12"
      And the destination holds the artifact and receipt of every run
      And the damaged runs are "<damaged runs>"
      When the reconcile task runs
      Then the report's first line is "<first line>"
      And the report's problem lines are "<problem lines>"

      Examples:
        | damaged runs                                     | first line                                            | problem lines                                      |
        | 2030-05-14 file missing; 2030-05-16 file changed | Backup files: 2 of 7 retained backups need attention  | 2030-05-14: file missing; 2030-05-16: file changed |
        | 2030-05-14 file missing                          | Backup files: 1 of 7 retained backups needs attention | 2030-05-14: file missing                           |

  Rule: The report and the log line disclose no private value

    # Exemption(e2e): the browser and HTTP client cannot read the reconcile Mix task's printed report or the post-run log line on the host; alternative-proof: bnest-app:test:integration / The report and the log line carry no private value
    @e2e-exempt
    Scenario: The report and the log line carry no private value
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-16" are absent
      When the reconcile task's printed report and the post-run log line are read
      Then neither contains a filesystem path, a digest, a destination identifier or a run ID

  Rule: A reconciliation that fails never fails the backup

    # Exemption(e2e): the browser and HTTP client cannot make the post-run reconciliation of a scheduled run raise inside the Bnest server; alternative-proof: bnest-app:test:integration / A reconciliation that raises leaves the backup verified
    @e2e-exempt
    Scenario: A reconciliation that raises leaves the backup verified
      Given a scheduled backup in an isolated destination whose post-run reconciliation raises
      When the scheduled run completes
      Then the run is recorded verified and its artifact and receipt exist
      And one path-free error line states that reconciliation failed

  Rule: The reconcile task's exit status follows its report

    # Exemption(e2e): the browser and HTTP client cannot run the reconcile Mix task or read its exit status and printed report; alternative-proof: bnest-app:test:integration / The task exits non-zero and names a <state> backup
    @e2e-exempt
    Scenario Outline: The task exits non-zero and names a <state> backup
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And <damage>
      When the reconcile task runs
      Then it exits non-zero
      And the report names the date "<date>" and the state file <state>
      And the report contains no path, digest, destination identifier or run ID

      Examples:
        | state   | date       | damage                                                                 |
        | missing | 2030-05-16 | the artifact and receipt of "2030-05-16" are absent                     |
        | changed | 2030-05-15 | the artifact of "2030-05-15" has a different digest from the ledger    |

    # Exemption(e2e): the browser and HTTP client cannot run the reconcile Mix task or read its exit status and printed summary; alternative-proof: bnest-app:test:integration / The task exits zero only when every expected run is present
    @e2e-exempt
    Scenario: The task exits zero only when every expected run is present
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      When the reconcile task runs
      Then it exits 0 and prints the summary line stating that all retained backups are present
      And it prints no per-date line

    # Exemption(e2e): the browser and HTTP client cannot make the server's ledger unreadable or run the reconcile Mix task; alternative-proof: bnest-app:test:integration / The task exits non-zero when the ledger is unreadable
    @e2e-exempt
    Scenario: The task exits non-zero when the ledger is unreadable
      Given an isolated destination and a ledger that cannot be read
      When the reconcile task runs
      Then it exits non-zero
      And the report's first line is "Backup files: could not be checked. Run mix bnest.backup.reconcile on the host."
      And the report states a path-free reason
      And the report contains no path, digest, destination identifier or run ID

    # Exemption(e2e): the browser and HTTP client cannot empty the server's run ledger or run the reconcile Mix task; alternative-proof: bnest-app:test:integration / The task does not report an empty ledger as present
    @e2e-exempt
    Scenario: The task does not report an empty ledger as present
      Given an isolated destination and a ledger holding no verified backup run
      When the reconcile task runs
      Then the report's first line is "Backup files: no verified backup to check yet"
      And it prints that there is no verified backup to check yet
      And it prints no date as present and does not state that backups are present
      And it exits non-zero

  Rule: Receipts and artifacts that retention does not own never influence it

    # Exemption(e2e): the browser and HTTP client cannot place foreign receipts and malformed files in the destination or run retention; alternative-proof: bnest-app:test:integration / Foreign receipts and unreceipted files are never removed or counted
    @e2e-exempt
    Scenario: Foreign receipts and unreceipted files are never removed or counted
      Given a destination holding owned pairs for eight WIB dates
      And receipts bearing another destination identifier, unreceipted artifacts and a malformed receipt
      When retention runs
      Then exactly the owned pairs outside the seven latest dates are removed
      And every foreign receipt, unreceipted artifact and malformed receipt is untouched
      And no foreign receipt changes which owned run is kept for a date

  Rule: The restore drill restores one artifact into a root it creates and removes

    # Exemption(e2e): the browser and HTTP client cannot run the restore drill Mix task or read its printed evidence and temporary root; alternative-proof: bnest-app:test:integration / The drill restores a synthetic artifact and prints redacted evidence
    @e2e-exempt
    Scenario: The drill restores a synthetic artifact and prints redacted evidence
      Given an isolated destination holding a synthetic artifact of 1 room, 3 messages and 2 push subscriptions with deliveries "pending" and "delivered"
      And a restorable regular file sits outside the destination
      And a directory sits inside the destination
      And a symbolic link inside the destination points to a restorable file outside it
      When the restore drill task is run against that artifact
      Then it exits 0 and its first line is "Restore drill: restored the artifact into a fresh isolated root"
      And it prints the line "Rooms readable: 1"
      And it prints the line "Messages readable: 3, in ascending order"
      And it prints the line "Push subscriptions: 2"
      And it prints the line "Delivery states: delivered, pending"
      And its last line is "Restore root: removed"

    # Exemption(e2e): the browser and HTTP client cannot read the restore drill's printed output; alternative-proof: bnest-app:test:integration / The drill prints no private value
    @e2e-exempt
    Scenario: The drill prints no private value
      Given an isolated destination holding a synthetic artifact
      When the restore drill task is run against that artifact
      Then it exits 0 and its first line is "Restore drill: restored the artifact into a fresh isolated root"
      And its output carries no message body, push credential, filesystem path or artifact name

    # Exemption(e2e): the browser and HTTP client cannot read the restore root or the destination bytes that the drill leaves behind; alternative-proof: bnest-app:test:integration / The drill leaves the destination unchanged and removes its root
    @e2e-exempt
    Scenario: The drill leaves the destination unchanged and removes its root
      Given an isolated destination holding a synthetic artifact
      When the restore drill task is run against that artifact
      Then it restored the artifact once into a fresh root that no longer exists
      And the destination listing and every file's bytes are unchanged
      And the live database is not opened

  Rule: The restore drill refuses an artifact that fails its integrity proof

    # Exemption(e2e): the browser and HTTP client cannot run the restore drill Mix task against a cut-short artifact or read its exit status and temporary root; alternative-proof: bnest-app:test:integration / The drill refuses an artifact cut short of its last bytes
    @e2e-exempt
    Scenario: The drill refuses an artifact cut short of its last bytes
      Given an isolated destination holding a synthetic artifact cut short of its last bytes
      When the restore drill task is run against that artifact
      Then it exits non-zero
      And it prints only the line "Restore drill: the artifact could not be restored."
      And it tried one restore of the artifact, and the root it created no longer exists
      And its output carries no message body, push credential, filesystem path or artifact name
      And the destination listing and every file's bytes are unchanged
      And the live database is not opened

  Rule: The restore drill restores only a regular file inside the configured destination

    # Exemption(e2e): the browser and HTTP client cannot run the restore drill Mix task with a target outside the destination or a directory or link inside it, or read its refusal; alternative-proof: bnest-app:test:integration / The drill refuses a target that is not a regular file inside the destination
    @e2e-exempt
    Scenario Outline: The drill refuses a target that is not a regular file inside the destination
      Given an isolated destination holding a synthetic artifact
      And <target>
      When <action>
      Then it exits non-zero
      And it prints only the line "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
      And nothing is restored
      And no restore root is created
      And the live database is not opened

      Examples:
        | target                                                                        | action                                                                                               |
        | a restorable regular file sits outside the destination                        | the restore drill task is run against the file outside the destination by its absolute path         |
        | a restorable regular file sits outside the destination                        | the restore drill task is run against the file outside the destination by a relative path that climbs out of it |
        | a directory sits inside the destination                                       | the restore drill task is run against that directory                                                 |
        | a symbolic link inside the destination points to a restorable file outside it | the restore drill task is run against that symbolic link                                             |
