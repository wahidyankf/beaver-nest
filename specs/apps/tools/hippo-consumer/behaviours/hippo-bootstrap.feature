Feature: Safe HIPPO consumer bootstrap
  The repository consumer must serialize release installation without letting stale or corrupt
  ownership records block installation forever or disrupt a live installer.

  Scenario: A cold cache installs once and a warm cache needs no transport
    Given a consumer cache holding no copy of the pinned release
    When the HIPPO consumer bootstrap runs, and then runs again with transport unavailable
    Then the release is downloaded exactly once and both runs execute it

  Scenario: Repository worker settings precede the caller's run arguments
    Given a caller invoking the HIPPO consumer bootstrap with a guarded run and its own arguments
    When the bootstrap executes the pinned release
    Then every repository worker mapping arrives ahead of the caller's arguments, whose order is
      unchanged

  Scenario: Tampered warm-cache payload never executes
    Given a cached executable has a wrong digest or embedded release identity
    When the HIPPO consumer bootstrap runs while release transport is unavailable
    Then it rejects the cached payload before that payload executes

  Scenario Outline: A downloaded release that fails verification is refused
    Given a downloaded release fails verification because <failure>
    When the HIPPO consumer bootstrap downloads and verifies that release
    Then it exits as invalid configuration and publishes nothing to the cache

    Examples:
      | failure                                                       |
      | its archive digest misses the checksum the consumer lock pins |
      | its reported identity has a duplicated or additional field    |

  Scenario: Non-exact stable release version is rejected
    Given the consumer lock contains a malformed or path-shaped release version
    When the HIPPO consumer bootstrap validates the lock
    Then it exits as invalid configuration before transport or cache escape

  Scenario: Unsupported platform is refused before any transport
    Given a host whose operating system or architecture is outside the published release matrix
    When the HIPPO consumer bootstrap resolves its platform
    Then it exits as invalid configuration without reading a checksum or contacting transport

  Scenario Outline: A caller waits while another caller is installing
    Given another consumer is installing the pinned release, and <its state>
    When this consumer tries to install the pinned release
    Then it waits and does not take over the other consumer's install

    Examples:
      | its state                                                |
      | its process is still running and its identity is intact  |
      | its process is still running and its identity is malformed |

  Scenario Outline: A caller takes over an install whose owner is gone
    Given <stale state>
    When this consumer tries to install the pinned release
    Then it takes over the abandoned install and installs the pinned release

    Examples:
      | stale state                                                              |
      | the earlier install's process has ended                                  |
      | the earlier install's process number now belongs to an unrelated process |
      | an earlier consumer crashed while it was starting its install            |

  Scenario Outline: Two callers starting together download once and both run the release
    Given two consumers start against <starting state>
    When both contend for the install
    Then both execute the release from one download

    Examples:
      | starting state                                          |
      | a cache holding no copy of the pinned release           |
      | a cache left by an earlier install whose process ended  |

  Scenario: Retention never deletes a release another consumer is using
    Given one consumer holds a live claim on the release it is running
    When another consumer with a different pinned version prunes superseded releases
    Then the claimed release survives and both consumers keep verified executables

  Scenario: Retention never evicts a release another repository still uses
    Given more repositories share one cache root than the ranked retention budget retains
    When every repository installs and prunes against its own distinct pinned version
    Then each repository keeps its release and none of them downloads a second time

  Scenario Outline: Retention reclaims releases left idle beyond its window
    Given a cache root holds release directories left untouched past the idle window
    And the host's stat command uses the <dialect> dialect
    When a consumer installs its pinned release and retention runs
    Then only the pinned release and the most recent idle fallbacks remain

    Examples:
      | dialect |
      | BSD     |
      | GNU     |
