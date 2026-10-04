Feature: Bnest scheduled backups

  Background:
    Given an approved user is logged in

  Scenario: Use the Dropbox-synced default
    Given no backup override exists
    When the daily backup destination resolves
    Then Bnest uses the ignored repository backup folder
    And the verified result exposes no private path

  Scenario: Save a safe override
    Given an administrator opened schedules and backups
    When the administrator saves a safe backup override
    Then Bnest stores the private backup configuration atomically
    And Bnest creates one idempotent setup claim for that destination

  # Exemption(e2e): durable restart state is an internal same-machine scheduler boundary; alternative-proof: bnest-app:test:integration / Persist a daily schedule across restart
  @e2e-exempt
  Scenario: Persist a daily schedule across restart
    Given the administrator saved an enabled daily WIB schedule
    When the scheduler restarts before the schedule is due
    Then the schedule remains enabled in SQLite
    And the same future UTC slot remains due

  # Exemption(e2e): missed-slot reconciliation is an internal same-machine scheduler boundary; alternative-proof: bnest-app:test:integration / Catch up only the latest missed slot
  @e2e-exempt
  Scenario: Catch up only the latest missed slot
    Given the scheduler missed more than one daily slot
    When startup reconciliation runs
    Then only the latest eligible slot is claimed
    And the next run advances to the next future day

  # Exemption(e2e): VACUUM and logical proof operate below every public application boundary; alternative-proof: bnest-app:test:integration / Back up authoritative SQLite
  @e2e-exempt
  Scenario: Back up authoritative SQLite
    Given a production backup claim is accepted
    When the backup handler runs
    Then only configured authoritative SQLite is snapshotted with VACUUM INTO
    And the candidate passes independent integrity and logical proof

  # Exemption(e2e): claim fencing and retry leases are internal same-machine coordination boundaries; alternative-proof: bnest-app:test:integration / Claim a slot once and recover
  @e2e-exempt
  Scenario: Claim a slot once and recover
    Given two coordinators observe the same slot and an attempt may lose its lease
    When both coordinators reconcile
    Then SQLite accepts one claim and backup tasks do not overlap
    And transient failure receives at most three persisted attempts

  # Exemption(e2e): verified history across more than seven WIB dates needs a controlled clock the public boundary lacks; alternative-proof: bnest-app:test:integration / Retain only owned verified artifacts
  @e2e-exempt
  Scenario: Retain only owned verified artifacts
    Given verified owned pairs span more than seven WIB dates beside unknown files
    When a new backup becomes verified
    Then Bnest keeps one newest owned pair for each retained WIB date
    And Bnest preserves unknown files and every previous destination

  # Exemption(e2e): coordinator dispatch and ledger updates are internal same-machine boundaries; alternative-proof: bnest-app:test:integration / Reuse one scheduler across contexts
  @e2e-exempt
  Scenario: Reuse one scheduler across contexts
    Given a second allowlisted family handler is persisted
    When its daily slot becomes due
    Then the shared coordinator and supervisor execute it
    And the shared ledger and contextual inventory record it

  # Exemption(e2e): expiration and retry occurrence accounting are internal scheduler policy boundaries; alternative-proof: bnest-app:test:integration / Expire schedules deterministically
  @e2e-exempt
  Scenario: Expire schedules deterministically
    Given schedules use never absolute and occurrence expiration policies
    When the coordinator reconciles claims and retries
    Then expiry blocks only ineligible future claims
    And retries do not consume occurrences or suppress the final occurrence

  Rule: Reconciliation reports a verified run whose artifact is absent or changed

    # Exemption(e2e): reconciliation reads the ledger and the destination below every public application boundary; alternative-proof: bnest-app:test:integration / A verified run without its artifact is reported missing
    @e2e-exempt
    Scenario: A verified run without its artifact is reported missing
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-16" are absent
      When reconciliation runs
      Then it reports the run of "2030-05-16" as missing with its artifact basename
      And it reports the runs of "2030-05-14" and "2030-05-15" as present

    # Exemption(e2e): reconciliation reads the ledger and the destination below every public application boundary; alternative-proof: bnest-app:test:integration / A changed artifact is reported changed
    @e2e-exempt
    Scenario: A changed artifact is reported changed
      Given an isolated ledger of 2 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact of "2030-05-15" has a different digest from the ledger
      When reconciliation runs
      Then it reports the run of "2030-05-15" as changed

    # Exemption(e2e): the retained-date window of retention needs a ledger spanning more than seven WIB dates below every public application boundary; alternative-proof: bnest-app:test:integration / A run older than the retained dates is not reported
    @e2e-exempt
    Scenario: A run older than the retained dates is not reported
      Given an isolated ledger of 8 verified runs on consecutive WIB dates from "2030-05-11"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-11" are absent because retention removed them
      When reconciliation runs
      Then it does not report the run of "2030-05-11"
      And it reports the 7 other runs as present

    # Exemption(e2e): two verified runs on one WIB date need a controlled ledger below every public application boundary; alternative-proof: bnest-app:test:integration / Only the newest verified run of a retained date is expected
    @e2e-exempt
    Scenario: Only the newest verified run of a retained date is expected
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the ledger holds an older verified run on "2030-05-15" whose artifact and receipt are absent
      When reconciliation runs
      Then it reports the newer run of "2030-05-15" as present
      And it does not report the older run of "2030-05-15"

    # Exemption(e2e): the read-only guarantee is observed on the destination files and the ledger rows below every public application boundary; alternative-proof: bnest-app:test:integration / Reconciliation never writes
    @e2e-exempt
    Scenario: Reconciliation never writes
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-16" are absent
      And an unknown file sits in the destination
      When reconciliation runs
      Then the destination listing and every file's bytes are unchanged
      And the ledger rows are unchanged

  Rule: The reconcile report states each result in one fixed wording

    # Exemption(e2e): the printed report is rendered by the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The report states that every retained backup is present
    @e2e-exempt
    Scenario: The report states that every retained backup is present
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      When the reconcile task runs
      Then the report's first line is "Backup files: all 3 retained backups are present"
      And the report has no problem line

    # Exemption(e2e): the printed report is rendered by the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The report counts several backups that need attention
    @e2e-exempt
    Scenario: The report counts several backups that need attention
      Given an isolated ledger of 7 verified runs on consecutive WIB dates from "2030-05-12"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-14" are absent
      And the artifact of "2030-05-16" has a different digest from the ledger
      When the reconcile task runs
      Then the report's first line is "Backup files: 2 of 7 retained backups need attention"
      And the report's problem lines are "2030-05-14: file missing" and "2030-05-16: file changed"

    # Exemption(e2e): the printed report is rendered by the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The report counts one backup that needs attention
    @e2e-exempt
    Scenario: The report counts one backup that needs attention
      Given an isolated ledger of 7 verified runs on consecutive WIB dates from "2030-05-12"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-14" are absent
      When the reconcile task runs
      Then the report's first line is "Backup files: 1 of 7 retained backups needs attention"
      And the report's only problem line is "2030-05-14: file missing"

    # Exemption(e2e): the printed report is rendered by the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The report says plainly when the check could not run
    @e2e-exempt
    Scenario: The report says plainly when the check could not run
      Given an isolated destination and a ledger that cannot be read
      When the reconcile task runs
      Then the report's first line is "Backup files: could not be checked. Run mix bnest.backup.reconcile on the host."
      And the report has no problem line

    # Exemption(e2e): the printed report is rendered by the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The report says plainly when there is nothing to check
    @e2e-exempt
    Scenario: The report says plainly when there is nothing to check
      Given an isolated destination and a ledger holding no verified backup run
      When the reconcile task runs
      Then the report's first line is "Backup files: no verified backup to check yet"
      And the report has no problem line

  Rule: The report and the log line disclose no private value

    # Exemption(e2e): the printed report and the post-run log line are internal output below every public application boundary; alternative-proof: bnest-app:test:integration / The report and the log line carry no private value
    @e2e-exempt
    Scenario: The report and the log line carry no private value
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-16" are absent
      When the reconcile task's printed report and the post-run log line are read
      Then neither contains a filesystem path, a digest, a destination identifier or a run ID

  Rule: A reconciliation that fails never fails the backup

    # Exemption(e2e): the scheduled run and its post-run reconciliation are an internal same-machine boundary; alternative-proof: bnest-app:test:integration / A reconciliation that raises leaves the backup verified
    @e2e-exempt
    Scenario: A reconciliation that raises leaves the backup verified
      Given a scheduled backup in an isolated destination whose post-run reconciliation raises
      When the scheduled run completes
      Then the run is recorded verified and its artifact and receipt exist
      And one path-free error line states that reconciliation failed

  Rule: The reconcile task's exit status follows its report

    # Exemption(e2e): the task's exit status is observed on the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The task exits zero only when every expected run is present
    @e2e-exempt
    Scenario: The task exits zero only when every expected run is present
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      When the reconcile task runs
      Then it exits 0 and prints the summary line stating that all retained backups are present
      And it prints no per-date line
      And it starts no scheduler

    # Exemption(e2e): the task's exit status is observed on the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The task exits non-zero when a run is missing
    @e2e-exempt
    Scenario: The task exits non-zero when a run is missing
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact and receipt of "2030-05-16" are absent
      When the reconcile task runs
      Then it exits non-zero
      And the report names the date "2030-05-16" and the state file missing
      And the report contains no path, digest, destination identifier or run ID

    # Exemption(e2e): the task's exit status is observed on the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The task exits non-zero when a run is changed
    @e2e-exempt
    Scenario: The task exits non-zero when a run is changed
      Given an isolated ledger of 3 verified runs on consecutive WIB dates from "2030-05-14"
      And the destination holds the artifact and receipt of every run
      And the artifact of "2030-05-15" has a different digest from the ledger
      When the reconcile task runs
      Then it exits non-zero
      And the report names the date "2030-05-15" and the state file changed
      And the report contains no path, digest, destination identifier or run ID

    # Exemption(e2e): the task's exit status is observed on the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The task exits non-zero when the ledger is unreadable
    @e2e-exempt
    Scenario: The task exits non-zero when the ledger is unreadable
      Given an isolated destination and a ledger that cannot be read
      When the reconcile task runs
      Then it exits non-zero
      And the report states a path-free reason
      And the report contains no path, digest, destination identifier or run ID

    # Exemption(e2e): the task's exit status is observed on the Mix task below every public application boundary; alternative-proof: bnest-app:test:integration / The task does not report an empty ledger as present
    @e2e-exempt
    Scenario: The task does not report an empty ledger as present
      Given an isolated destination and a ledger holding no verified backup run
      When the reconcile task runs
      Then it prints that there is no verified backup to check yet
      And it prints no date as present and does not state that backups are present
      And it exits non-zero
      And it starts no scheduler

  Rule: Receipts and artifacts that retention does not own never influence it

    # Exemption(e2e): retention over a destination holding foreign and malformed files is an internal same-machine boundary; alternative-proof: bnest-app:test:integration / Foreign receipts and unreceipted files are never removed or counted
    @e2e-exempt
    Scenario: Foreign receipts and unreceipted files are never removed or counted
      Given a destination holding owned pairs for eight WIB dates
      And receipts bearing another destination identifier, unreceipted artifacts and a malformed receipt
      When retention runs
      Then exactly the owned pairs outside the seven latest dates are removed
      And every foreign receipt, unreceipted artifact and malformed receipt is untouched
      And no foreign receipt changes which owned run is kept for a date

  Rule: A test cannot reach the production backup directory

    # Exemption(e2e): the test environment's destination resolution is an internal configuration boundary; alternative-proof: bnest-app:test:integration / The test environment refuses the production backup destination
    @e2e-exempt
    Scenario: The test environment refuses the production backup destination
      Given the test environment
      When a test resolves the repository's default backup directory
      Then the operation fails closed before any file is created
      And the listing of the default backup directory is unchanged

  Rule: The restore drill restores one artifact into a root it creates and removes

    # Exemption(e2e): the restore drill is a Mix task whose temporary restore root and printed evidence lie below every public application boundary; alternative-proof: bnest-app:test:integration / The drill restores a synthetic artifact and prints redacted evidence
    @e2e-exempt
    Scenario: The drill restores a synthetic artifact and prints redacted evidence
      Given an isolated destination holding a synthetic artifact of 1 room, 3 messages and 2 push subscriptions with deliveries "pending" and "delivered"
      When the restore drill task is run against that artifact
      Then it exits 0 and its first line is "Restore drill: restored the artifact into a fresh isolated root"
      And it prints the line "Rooms readable: 1"
      And it prints the line "Messages readable: 3, in ascending order"
      And it prints the line "Push subscriptions: 2"
      And it prints the line "Delivery states: delivered, pending"
      And its last line is "Restore root: removed"

    # Exemption(e2e): the restore drill is a Mix task whose printed evidence lies below every public application boundary; alternative-proof: bnest-app:test:integration / The drill prints no private value
    @e2e-exempt
    Scenario: The drill prints no private value
      Given an isolated destination holding a synthetic artifact
      When the restore drill task is run against that artifact
      Then it exits 0 and its first line is "Restore drill: restored the artifact into a fresh isolated root"
      And its output carries no message body, push credential, filesystem path or artifact name

    # Exemption(e2e): the restore root, the destination files and the live database are observed below every public application boundary; alternative-proof: bnest-app:test:integration / The drill leaves the destination unchanged and removes its root
    @e2e-exempt
    Scenario: The drill leaves the destination unchanged and removes its root
      Given an isolated destination holding a synthetic artifact
      When the restore drill task is run against that artifact
      Then it restored the artifact once into a fresh root that no longer exists
      And the destination listing and every file's bytes are unchanged
      And the live database is not opened

  Rule: The restore drill restores only a regular file inside the configured destination

    # Exemption(e2e): the restore drill is a Mix task whose target classification is observed on its result below every public application boundary; alternative-proof: bnest-app:test:integration / A regular file inside the destination restores beside the entries it refuses
    @e2e-exempt
    Scenario: A regular file inside the destination restores beside the entries it refuses
      Given an isolated destination holding a synthetic artifact
      And a restorable regular file sits outside the destination
      And a directory sits inside the destination
      And a symbolic link inside the destination points to a restorable file outside it
      When the restore drill task is run against that artifact
      Then it exits 0 and its first line is "Restore drill: restored the artifact into a fresh isolated root"

    # Exemption(e2e): the refusal is observed on the Mix task result, the temporary directory and the live database below every public application boundary; alternative-proof: bnest-app:test:integration / A regular file outside the destination is refused
    @e2e-exempt
    Scenario: A regular file outside the destination is refused
      Given an isolated destination holding a synthetic artifact
      And a restorable regular file sits outside the destination
      When the restore drill task is run against the file outside the destination by its absolute path
      Then it exits non-zero
      And it prints only the line "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
      And nothing is restored
      And no restore root is created
      And the live database is not opened

    # Exemption(e2e): the refusal is observed on the Mix task result, the temporary directory and the live database below every public application boundary; alternative-proof: bnest-app:test:integration / A relative path that climbs out of the destination is refused
    @e2e-exempt
    Scenario: A relative path that climbs out of the destination is refused
      Given an isolated destination holding a synthetic artifact
      And a restorable regular file sits outside the destination
      When the restore drill task is run against the file outside the destination by a relative path that climbs out of it
      Then it exits non-zero
      And it prints only the line "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
      And nothing is restored
      And no restore root is created
      And the live database is not opened

    # Exemption(e2e): the refusal is observed on the Mix task result, the temporary directory and the live database below every public application boundary; alternative-proof: bnest-app:test:integration / A directory inside the destination is refused
    @e2e-exempt
    Scenario: A directory inside the destination is refused
      Given an isolated destination holding a synthetic artifact
      And a directory sits inside the destination
      When the restore drill task is run against that directory
      Then it exits non-zero
      And it prints only the line "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
      And nothing is restored
      And no restore root is created
      And the live database is not opened

    # Exemption(e2e): the refusal is observed on the Mix task result, the temporary directory and the live database below every public application boundary; alternative-proof: bnest-app:test:integration / A symbolic link inside the destination is refused
    @e2e-exempt
    Scenario: A symbolic link inside the destination is refused
      Given an isolated destination holding a synthetic artifact
      And a symbolic link inside the destination points to a restorable file outside it
      When the restore drill task is run against that symbolic link
      Then it exits non-zero
      And it prints only the line "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
      And nothing is restored
      And no restore root is created
      And the live database is not opened
