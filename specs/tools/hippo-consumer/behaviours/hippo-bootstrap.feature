Feature: Safe HIPPO consumer bootstrap
  The repository consumer must serialize release installation without letting stale or corrupt
  ownership records block installation forever or disrupt a live installer.

  Scenario: Tampered warm-cache payload never executes
    Given a cached executable has a wrong digest or embedded release identity
    When the HIPPO consumer bootstrap runs while release transport is unavailable
    Then it rejects the cached payload before that payload executes

  Scenario: Non-exact stable release version is rejected
    Given the consumer lock contains a malformed or path-shaped release version
    When the HIPPO consumer bootstrap validates the lock
    Then it exits as invalid configuration before transport or cache escape

  Scenario: Release identity envelope must match exactly
    Given a downloaded release reports a duplicated or additional identity field
    When the HIPPO consumer bootstrap validates the extracted executable
    Then it rejects the release without publishing it to the cache

  Scenario: Matching live install-lock owner remains protected
    Given an install lock records a live process and its matching process-start identity
    When another HIPPO consumer bootstrap tries to install the pinned release
    Then the bootstrap waits without reclaiming the live owner's install lock

  Scenario: Malformed identity for a live install-lock owner fails closed
    Given an install lock records a live process with a malformed process-start identity
    When another HIPPO consumer bootstrap tries to install the pinned release
    Then the bootstrap waits without treating malformed metadata as proof of staleness

  Scenario: Reused live PID with a different valid identity is reclaimed
    Given an install lock records a live process with a different valid process-start identity
    When another HIPPO consumer bootstrap tries to install the pinned release
    Then the bootstrap reclaims the stale lock and installs the pinned release

  Scenario: Dead install-lock owner is reclaimed
    Given an install lock records a process that is no longer alive
    When another HIPPO consumer bootstrap tries to install the pinned release
    Then the bootstrap reclaims the abandoned lock and installs the pinned release

  Scenario: Crash before install-lock metadata publication is recoverable
    Given an earlier consumer left an incomplete legacy lock or an orphan prepared owner record
    When another HIPPO consumer bootstrap tries to install the pinned release
    Then it reclaims only positively stale state while fresh or live preparations remain protected

  Scenario: Concurrent stale reclaimers preserve a replacement live owner
    Given a stale install record and two concurrent consumer contenders
    When one consumer reclaims the record and publishes live ownership during installation
    Then the replacement remains owned and the pinned release downloads exactly once

  Scenario: Install guard storage stays bounded across release versions
    Given one consumer cache has installed several distinct pinned release versions
    When release-directory retention prunes superseded versions
    Then the cache retains exactly one install guard for the whole cache root

  Scenario: Retention never deletes a release another consumer is installing
    Given one consumer is publishing an install into its pinned release directory
    When another consumer with a different pinned version prunes superseded releases
    Then the release being installed survives and both consumers keep verified executables

  Scenario: Retention never evicts a release another repository still uses
    Given more repositories share one cache root than the ranked retention budget retains
    When every repository installs and prunes against its own distinct pinned version
    Then each repository keeps its release and none of them downloads a second time

  Scenario: Release ranking reads real timestamps on every supported platform
    Given a consumer cache holds release directories on a platform whose stat rejects the other
      platform's timestamp format
    When retention ranks those directories by how recently they were used
    Then it ranks them by their real timestamps rather than by diagnostic output

  Scenario: Retention reclaims releases left idle beyond its window
    Given a cache root holds release directories left untouched past the idle window
    When a consumer installs its pinned release and retention runs
    Then only the pinned release and the most recent idle fallbacks remain
