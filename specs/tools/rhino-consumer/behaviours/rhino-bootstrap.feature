Feature: Safe RHINO consumer bootstrap
  The repository consumer must serialize release installation without letting stale or corrupt
  ownership records block installation forever or disrupt a live installer, and must share a machine
  with the HIPPO consumer without either wrapper reaching the other's state.

  Scenario: A cold cache installs once and a warm cache needs no transport
    Given a consumer cache holding no copy of the pinned release
    When the RHINO consumer bootstrap runs, and then runs again with transport unavailable
    Then the release is downloaded exactly once and both runs execute it

  Scenario: The caller's argument vector reaches the release unchanged
    Given a caller invoking the RHINO consumer bootstrap with a multi-word command and a flag,
      neither of which is the bootstrap's own resolve request
    When the bootstrap executes the pinned release
    Then the release receives exactly those arguments in order, with none added or removed

  Scenario: One resolution serves a whole gate
    Given a caller that must run several checks against the same pinned release
    When it asks the RHINO consumer bootstrap to resolve once and run its command
    Then the command runs with the verified executable's path in its environment, and the bootstrap
      verifies that executable once rather than once per check

  Scenario: A resolved run stays claimed for as long as its command runs
    Given the RHINO consumer bootstrap resolving once for a caller's command
    When that command inspects the cache while it is still running
    Then a live release claim for the running process is present, so retention cannot reclaim the
      release the command is about to use

  Scenario: Resolving once does not skip payload verification
    Given a cached executable has a wrong digest or embedded release identity
    When a caller asks the RHINO consumer bootstrap to resolve once and run its command
    Then the bootstrap refuses before the caller's command runs at all

  Scenario: A resolve request without a command is refused
    Given a caller that asks the RHINO consumer bootstrap to resolve once but names no command
    When the bootstrap parses that request
    Then it refuses as an invalid invocation and executes nothing

  Scenario: Tampered warm-cache payload never executes
    Given a cached executable has a wrong digest or embedded release identity
    When the RHINO consumer bootstrap runs while release transport is unavailable
    Then it rejects the cached payload before that payload executes

  Scenario: A downloaded archive whose digest misses the pin never executes
    Given the consumer lock pins a checksum the published archive does not match
    When the RHINO consumer bootstrap downloads that archive
    Then it exits as invalid configuration without publishing or executing the payload

  Scenario: Non-exact stable release version is rejected
    Given the consumer lock contains a malformed or path-shaped release version
    When the RHINO consumer bootstrap validates the lock
    Then it exits as invalid configuration before transport or cache escape

  Scenario: Release identity envelope must match exactly
    Given a downloaded release reports a duplicated or additional identity field
    When the RHINO consumer bootstrap validates the extracted executable
    Then it rejects the release without publishing it to the cache

  Scenario: Unsupported platform is refused before any transport
    Given a host whose operating system or architecture is outside the published release matrix
    When the RHINO consumer bootstrap resolves its platform
    Then it exits as invalid configuration without reading a checksum or contacting transport

  Scenario: Matching live install-lock owner remains protected
    Given an install lock records a live process and its matching process-start identity
    When another RHINO consumer bootstrap tries to install the pinned release
    Then the bootstrap waits without reclaiming the live owner's install lock

  Scenario: Malformed identity for a live install-lock owner fails closed
    Given an install lock records a live process with a malformed process-start identity
    When another RHINO consumer bootstrap tries to install the pinned release
    Then the bootstrap waits without treating malformed metadata as proof of staleness

  Scenario: Reused live PID with a different valid identity is reclaimed
    Given an install lock records a live process with a different valid process-start identity
    When another RHINO consumer bootstrap tries to install the pinned release
    Then the bootstrap reclaims the stale lock and installs the pinned release

  Scenario: Dead install-lock owner is reclaimed
    Given an install lock records a process that is no longer alive
    When another RHINO consumer bootstrap tries to install the pinned release
    Then the bootstrap reclaims the abandoned lock and installs the pinned release

  Scenario: Crash before install-lock metadata publication is recoverable
    Given an earlier consumer left an incomplete legacy lock or an orphan prepared owner record
    When another RHINO consumer bootstrap tries to install the pinned release
    Then it reclaims only positively stale state while fresh or live preparations remain protected

  Scenario: Concurrent cold callers install from exactly one verified download
    Given two consumers start against a cache holding no copy of the pinned release
    When both contend for the install
    Then both execute the release from one download and no ownership record survives

  Scenario: Concurrent stale reclaimers preserve a replacement live owner
    Given a stale install record and two concurrent consumer contenders
    When one consumer reclaims the record and publishes live ownership during installation
    Then the replacement remains owned and the pinned release downloads exactly once

  Scenario: A consumer never removes an install lock it did not publish
    Given a consumer's install lock has been replaced by another live owner's record
    When that consumer finishes installing and releases its lock
    Then it leaves the replacement in place rather than admitting a third installer

  Scenario: Install guard storage stays bounded across release versions
    Given one consumer cache has installed several distinct pinned release versions
    When release-directory retention prunes superseded versions
    Then the cache retains exactly one install guard for the whole cache root

  Scenario: Retention never deletes a release another consumer is using
    Given one consumer holds a live claim on the release it is running
    When another consumer with a different pinned version prunes superseded releases
    Then the claimed release survives and both consumers keep verified executables

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

  Scenario: The two consumer bootstraps never reach each other's state
    Given this repository ships both the RHINO and the HIPPO consumer wrappers
    When each resolves its cache root, install guard, release directory, and transport under
      one shared machine environment
    Then neither wrapper touches a path the other touched, neither root lies inside the other,
      and each honours only its own cache-root override
