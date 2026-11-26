Feature: Safe RHINO consumer bootstrap
  The repository consumer must serialize release installation without letting stale or corrupt
  ownership records block installation forever or disrupt a live installer, and must share a machine
  with the HIPPO consumer without either wrapper reaching the other's state.

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: A cold cache installs once and a warm cache needs no transport
    Given a consumer cache holding no copy of the pinned release
    When the RHINO consumer bootstrap runs, and then runs again with transport unavailable
    Then the release is downloaded exactly once and both runs execute it

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: The caller's argument vector reaches the release unchanged
    Given a caller invoking the RHINO consumer bootstrap with a multi-word command and a flag
    When the bootstrap executes the pinned release
    Then the release receives exactly those arguments in order, with none added or removed

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: Tampered warm-cache payload never executes
    Given a cached executable has a wrong digest or embedded release identity
    When the RHINO consumer bootstrap runs while release transport is unavailable
    Then it rejects the cached payload before that payload executes

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: A downloaded release that fails verification is refused
    Given a downloaded release fails verification because <failure>
    When the RHINO consumer bootstrap downloads and verifies that release
    Then it exits as invalid configuration and publishes nothing to the cache, without executing the payload

    Examples:
      | failure                                                       |
      | its archive digest misses the checksum the consumer lock pins |
      | its reported identity has a duplicated or additional field    |

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: Non-exact stable release version is rejected
    Given the consumer lock contains a malformed or path-shaped release version
    When the RHINO consumer bootstrap validates the lock
    Then it exits as invalid configuration before transport or cache escape

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: A pinned release candidate installs and runs
    Given the consumer lock pins an exact candidate tag and the extracted release reports its stable product version
    When the RHINO consumer bootstrap validates and installs that candidate
    Then it verifies the stable identity, retains the exact candidate cache path, and the release runs, and a second run
      needs no download

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: Unsupported platform is refused before any transport
    Given a host whose operating system or architecture is outside the published release matrix
    When the RHINO consumer bootstrap resolves its platform
    Then it exits as invalid configuration without reading a checksum or contacting transport

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: A caller waits while another caller is installing
    Given another consumer is installing the pinned release, and <its state>
    When this consumer tries to install the pinned release
    Then it waits and does not take over the other consumer's install

    Examples:
      | its state                                                  |
      | its process is still running and its identity is intact    |
      | its process is still running and its identity is malformed |

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: A caller takes over an install whose owner is gone
    Given <stale state>
    When this consumer tries to install the pinned release
    Then it takes over the abandoned install and installs the pinned release, reclaiming only positively stale state
      while fresh or live preparations remain protected

    Examples:
      | stale state                                                              |
      | the earlier install's process has ended                                  |
      | the earlier install's process number now belongs to an unrelated process |
      | an earlier consumer crashed while it was starting its install            |
      | an incomplete legacy lock left by an earlier consumer                    |
      | an orphan prepared owner record left by an earlier consumer              |

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: Two callers starting together download once and both run the release
    Given two consumers start against <starting state>
    When both contend for the install
    Then both execute the release from one download, a live replacement owner stays owned while the other contends,
      and no ownership record survives

    Examples:
      | starting state                                          |
      | a cache holding no copy of the pinned release           |
      | a cache left by an earlier install whose process ended  |

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: Retention never deletes a release another consumer is using
    Given one consumer holds a live claim on the release it is running
    When another consumer with a different pinned version prunes superseded releases
    Then the claimed release survives and both consumers keep verified executables

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: Retention never evicts a release another repository still uses
    Given more repositories share one cache root than the ranked retention budget retains
    When every repository installs and prunes against its own distinct pinned version
    Then each repository keeps its release and none of them downloads a second time

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: Retention reclaims releases left idle beyond its window
    Given a cache root holds release directories left untouched past the idle window
    And the host's stat command uses the <dialect> dialect
    When a consumer installs its pinned release and retention runs
    Then only the pinned release and the most recent idle fallbacks remain, because retention ranks releases by their
      real timestamps rather than by diagnostic output

    Examples:
      | dialect |
      | BSD     |
      | GNU     |

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: Installing both tools on one machine keeps their caches apart
    Given this repository ships both the RHINO and the HIPPO consumer wrappers
    When each consumer runs once under one shared machine environment with transport unavailable
    Then neither consumer touches a path the other touched, neither cache root lies inside the other,
      and each requests only its own pinned release

  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario: Each tool honours only its own cache-root setting
    Given this repository ships both the RHINO and the HIPPO consumer wrappers
    When each consumer runs with its own cache-root setting, and again with only the other tool's setting
    Then it installs only under its own setting, and with only the other tool's setting it keeps to its
      default cache root

  # Carries BN-BOOT-15: pin refusals exit 125 before any transport.
  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: A missing, duplicated, or malformed pin exits 125 before any transport
    Given the consumer pin is <pin state>
    When the RHINO consumer bootstrap validates the pin
    Then it exits 125 with "<message>" and starts no download

    Examples:
      | pin state                    | message                                                      |
      | no rhino.lock                | rhino has no pin at rhino.lock, and an unpinned gate is not a gate |
      | a key declared twice         | rhino lock has missing or duplicate version                  |
      | a key missing                | rhino lock has missing or duplicate version                  |
      | an invalid commit            | rhino lock has an invalid commit                             |
      | an invalid platform checksum | rhino lock has an invalid checksum                           |

  # Carries BN-BOOT-16 and BN-DOC-03: bounded waits exit 124.
  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: A bounded wait for the install guard or lock that runs out exits 124
    Given <contention> holds the install path
    When the RHINO consumer bootstrap waits for it
    Then it exits 124 with "<message>"

    Examples:
      | contention                                     | message                                                |
      | the shared install guard that is never granted | rhino bootstrap timed out waiting for its install guard |
      | the install lock held by a live owner          | rhino bootstrap timed out waiting for its install lock  |

  # Carries BN-BOOT-17: missing lock tool exits 125 before the guard opens.
  # Exemption(e2e): shell wrappers have no application boundary; alternative-proof: .github/scripts/test-rhino-bootstrap.sh
  @e2e-exempt
  Scenario Outline: A host without flock or lockf exits 125
    Given the host is <platform> without its lock tool
    When the RHINO consumer bootstrap opens the install guard
    Then it exits 125 with "<message>" before the guard opens

    Examples:
      | platform | message                                  |
      | Linux    | rhino bootstrap requires flock on Linux  |
      | Darwin   | rhino bootstrap requires lockf on Darwin |
