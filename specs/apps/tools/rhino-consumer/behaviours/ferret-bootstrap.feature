Feature: Safe FERRET consumer bootstrap
  The repository records its harness telemetry with the pinned FERRET release.
  Every invocation dispatches through ./ferret rather than whatever ferret
  happens to be on PATH. Verification is unconditional and happens before
  execution. A cached copy is re-digested every run.

  # Carries BN-BOOT-19: cold cache downloads and verifies, warm cache re-digests.
  # Exemption(e2e): shell wrapper with no application boundary; alternative-proof: .github/scripts/test-ferret-bootstrap.sh
  @e2e-exempt
  Scenario: ./ferret installs and verifies the pinned FERRET before running it
    Given a cache holding no copy of the pinned FERRET
    When ./ferret installs the pinned release and runs it with the caller's arguments
    Then it downloads ferret-cli_<version>.pyz and checksums.txt once
    And it checks the pin against the published digest and the bytes
    And it checks the reported ferret <version>
    And it publishes by atomic rename and execs it with the caller's arguments
    And a warm cache is re-digested on every run and needs no transport

  # Carries BN-BOOT-20: refusal outline, no fallback, no bounded wait.
  # Exemption(e2e): shell wrapper with no application boundary; alternative-proof: .github/scripts/test-ferret-bootstrap.sh
  @e2e-exempt
  Scenario Outline: ./ferret refuses an unpinned fallback or a failed install
    Given the FERRET install fails because <failure>
    When ./ferret attempts the install
    Then it exits 125 with "<message>" and publishes and runs nothing

    Examples:
      | failure                              | message                                                                      |
      | the archive fetch fails              | the pinned FERRET could not be fetched, and this wrapper will not fall back to an unpinned one |
      | the checksums fetch fails            | the release checksums could not be fetched                                   |
      | the release publishes another digest | the release publishes a different digest for ferret-cli_v0.4.0.pyz than the pin declares |
      | the fetched bytes miss the pin       | the fetched artifact does not match the pinned digest                        |
      | the artifact reports another version | the pinned artifact reports a version the pin does not name                  |
      | a cached binary with a wrong digest  | the installed FERRET did not verify immediately after installation           |

  # Carries BN-BOOT-15 (ferret rows): pin refusals exit 125 before any transport.
  # A ferret on PATH is never used, and ./ferret has no bounded wait, so it never exits 124.
  # Exemption(e2e): shell wrapper with no application boundary; alternative-proof: .github/scripts/test-ferret-bootstrap.sh
  @e2e-exempt
  Scenario Outline: A missing, duplicated, or malformed pin makes ./ferret refuse with 125
    Given the FERRET pin is <pin state>
    When ./ferret validates the pin
    Then it exits 125 with "[ferret] <message>" and starts no download

    Examples:
      | pin state                  | message                                                      |
      | no ferret.lock             | there is no pin at ferret.lock, and an unpinned recorder is not a record |
      | a duplicate key            | the pin declares version more than once                      |
      | a bad version              | the pin declares an invalid stable version                   |
      | a bad commit               | the pin declares an invalid commit                           |
      | a bad artifact digest      | the pin declares an invalid artifact digest                  |
