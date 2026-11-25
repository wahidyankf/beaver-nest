Feature: Bnest release and deploy

  Rule: The release run builds an immutable artifact and reports one JSON result

  # Carries BN-REL-01 and BN-DOC-04.
  # A real run needs host state no integration boundary provides; the scenario
  # carries an integration reference to its model execution below, and the
  # release:test suite is the executable proof.
  # Exemption(e2e): E2E runs inside the gate manifest and cannot run the release that runs it; alternative-proof: release:test / release:run builds an immutable artifact, promotes it, and prints one JSON result
  @e2e-exempt
  Scenario: release:run builds an immutable artifact, promotes it, and prints one JSON result
    Given a release host records its calls
    When release:run runs for the revision
    Then the recorded call order is "preflight gates build migration prepare promote routed drain converge"
    And the printed line is one JSON result with outcome "passed"

  # The queued and deferred rows need host state no integration boundary
  # provides; the scenario carries an integration reference to its model
  # execution below, and the failed row is also proven by a child process.
  # Exemption(e2e): the release runs the E2E gate and cannot be run from inside it; alternative-proof: release:test / release exits 0 for passed, queued, and deferred and 1 for every other outcome
  @e2e-exempt
  Scenario Outline: release exits 0 for passed, queued, and deferred and 1 for every other outcome
    Given a release host throws "<category>" with outcome "<outcome>"
    When release:run runs for the revision
    Then the printed JSON carries outcome "<outcome>" and the exit status is <status>

    Examples:
      | category    | outcome     | status |
      | (none)      | passed      | 0      |
      | concurrency | queued      | 0      |
      | capacity    | deferred    | 0      |
      | preflight   | failed      | 1      |
      | concurrency | rolled-back | 1      |

  Rule: Release modes re-promote the routed artifact or stop unknown modes

  # The routed slots, Caddy and the artifact directory are host state; the
  # scenario carries an integration reference to its model execution below.
  # Exemption(e2e): the release cannot run from inside its own gate; alternative-proof: bnest-app-fe-e2e:test:e2e / Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate
  @e2e-exempt
  Scenario: release --mode experience re-promotes the routed artifact with the family chat flags on
    Given an experience host records its calls
    When release --mode experience runs for the routed revision
    Then it never builds, migrates, or discards an artifact and prepares with the family chat flags on
    And its only gate is the experience release E2E

  # Exemption(e2e): the mode check runs below every public boundary; alternative-proof: bnest-app:test:integration / An unknown release mode stops with a configuration error
  @e2e-exempt
  Scenario: An unknown release mode stops with a configuration error
    Given the release arguments are "--mode bogus"
    When the mode is parsed
    Then it throws configuration "Unknown release mode: bogus" before any host exists

  Rule: Artifact steps run one step each against the immutable artifact

  # The build row needs a full application build no test boundary performs; the
  # migrate and converge rows are proven by child processes against a fake
  # artifact binary.
  # Exemption(e2e): production artifact steps run on the host; alternative-proof: release:test / release:build, release:migrate, and release:converge each run one step against the immutable artifact
  @e2e-exempt
  Scenario Outline: release:build, release:migrate, and release:converge each run one step against the immutable artifact
    Given the release artifact for "0123456789abcdef0123456789abcdef01234567" is "<artifact>" and the worktree is "<worktree>"
    When the "<command>" command runs with its doubles
    Then it records "<calls>" and prints "<prints>"
    And a failure reports "<failure>"

    Examples:
      | command          | artifact | worktree        | calls                                               | prints                                   | failure                                                      |
      | release:build    | missing  | isolated        | npm ci, mix release steps, copy artifact            | 0123456789abcdef0123456789abcdef01234567 | none                                                         |
      | release:build    | present  | isolated        | (none)                                              | (none)                                   | Release 0123456789abcdef0123456789abcdef01234567 already exists; refuse to overwrite an immutable artifact. |
      | release:build    | missing  | inside checkout | (none)                                              | (none)                                   | BNEST_DEPLOY_WORKTREE must be an isolated Git worktree.      |
      | release:migrate  | present  | (none)          | migration eval with the production environment      | (none)                                   | none                                                         |
      | release:migrate  | missing  | (none)          | (none)                                              | (none)                                   | Release 0123456789abcdef0123456789abcdef01234567 does not exist. |
      | release:converge | present  | (none)          | converge eval with the production environment       | (none)                                   | none                                                         |
      | release:converge | missing  | (none)          | (none)                                              | (none)                                   | Release 0123456789abcdef0123456789abcdef01234567 does not exist. |

  Rule: Slot commands take a blue or green slot and promote through Caddy

  # Exemption(e2e): the slot commands need real service units on the host; alternative-proof: bnest-app:test:integration / deploy:prepare and deploy:promote take a blue or green slot
  @e2e-exempt
  Scenario Outline: deploy:prepare and deploy:promote take a blue or green slot
    Given the deploy command "<command>" is invoked with "<args>" against "<state>"
    When the slot command runs with its doubles
    Then it records "<calls>" and refuses "<refusal>"

    Examples:
      | command        | args                                                   | state                     | calls                                                        | refusal                                            |
      | deploy:prepare  | --slot blue --revision 0123456789abcdef0123456789abcdef01234567 | fresh                     | install service, await ready, write metadata                 | none                                               |
      | deploy:prepare  | --slot green --revision 0123456789abcdef0123456789abcdef01234567 | fresh                     | install service, await ready, write metadata                 | none                                               |
      | deploy:prepare  | --slot teal --revision 0123456789abcdef0123456789abcdef01234567 | fresh                     | (none)                                                       | --slot must be blue or green.                      |
      | deploy:prepare  | --slot blue                                            | fresh                     | (none)                                                       | --revision is required; run release:build first.   |
      | deploy:prepare  | (no arguments)                                         | fresh                     | (none)                                                       | --slot must be blue or green.                      |
      | deploy:promote  | --slot green                                           | blue active, green ready  | write Caddyfile, validate, reload, write state, print status | none                                               |
      | deploy:promote  | --slot blue                                            | blue active, green ready  | (none)                                                       | blue is already active.                            |
      | deploy:promote  | --slot green                                           | blue active, green missing | (none)                                                      | green has not been prepared.                       |
      | deploy:promote  | --slot teal                                            | blue active, green ready  | (none)                                                       | --slot must be blue or green.                      |
      | deploy:promote  | --slot blue                                            | fresh                     | (none)                                                       | blue has not been prepared.                        |

  # The timeout row needs 60 seconds of wall time no test boundary shortens;
  # the ready row is proven by a child process with a curl double.
  # Exemption(e2e): production slot ports are host state; alternative-proof: release:test / Promotion waits up to 60 seconds for the slot to report its revision
  @e2e-exempt
  Scenario Outline: Promotion waits up to 60 seconds for the slot to report its revision
    Given the "<slot>" slot reports "<report>"
    When the readiness wait runs with its doubles
    Then it ends with "<ending>"

    Examples:
      | slot  | report               | ending                                              |
      | blue  | the revision at once | ready                                               |
      | green | another revision     | green did not become ready within 60 seconds.       |

  # Exemption(e2e): rollback drives real Caddy and slot services; alternative-proof: bnest-app:test:integration / deploy:rollback returns traffic to the previous slot or refuses
  @e2e-exempt
  Scenario Outline: deploy:rollback returns traffic to the previous slot or refuses
    Given the previous slot is "<previous>"
    When rollback runs with its doubles
    Then it activates "<active>" or refuses "<refusal>"

    Examples:
      | previous | active | refusal                                          |
      | blue     | blue   | none                                             |
      | (none)   | (none) | No previous slot is available for rollback.      |

  # Exemption(e2e): retiring a real user service needs the host's service manager; alternative-proof: bnest-app:test:integration / deploy:retire stops a slot through the platform service adapter and refuses the active slot
  @e2e-exempt
  Scenario Outline: deploy:retire stops a slot through the platform service adapter and refuses the active slot
    Given the platform is "<platform>" and the active slot is "<active>"
    When retire runs for "<slot>" with its doubles
    Then it stops "<stopped>" or refuses "<refusal>"

    Examples:
      | platform | active | slot  | stopped                                 | refusal                              |
      | linux    | blue   | green | green through systemctl --user disable --now | none                            |
      | darwin   | blue   | green | green through launchctl bootout         | none                                 |
      | linux    | blue   | blue  | (none)                                  | Refuse to retire the active slot.    |

  Rule: The deployment dispatcher and its configuration refuse bad input

  # Exemption(e2e): the dispatcher runs below every public boundary; alternative-proof: bnest-app:test:integration / A missing revision or an unknown deployment command is refused
  @e2e-exempt
  Scenario Outline: A missing revision or an unknown deployment command is refused
    Given the deployment arguments are "<args>"
    When the dispatcher runs with its doubles
    Then it refuses "<message>" on stderr with exit 1 and no side effect

    Examples:
      | args                        | message                                            |
      | deploy:prepare --slot blue   | --revision is required; run release:build first.   |
      | release:migrate             | --revision is required; run release:build first.   |
      | release:converge            | --revision is required; run release:build first.   |
      | deploy:unknown              | Unknown deployment command: deploy:unknown        |
      | (no arguments)              | Unknown deployment command: (missing)              |

  # Exemption(e2e): operator configuration is checked below every public boundary; alternative-proof: bnest-app:test:integration / A deploy root inside the repository or a production origin that is not a bare HTTPS origin is refused
  @e2e-exempt
  Scenario Outline: A deploy root inside the repository or a production origin that is not a bare HTTPS origin is refused
    Given the deploy root is "<root>" and the production origin is "<origin>"
    When the deployment configuration is checked
    Then it refuses "<message>"
    And release:run reports outcome "failed" with errorCategory "configuration"

    Examples:
      | root              | origin                            | message                                                              |
      | inside checkout   | https://service.example           | BNEST_DEPLOY_ROOT must be outside the repository working tree.       |
      | (missing)         | https://service.example           | BNEST_DEPLOY_ROOT must point to machine-local deployment state.      |
      | /tmp/bnest-deploy | (missing)                         | BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin.       |
      | /tmp/bnest-deploy | http://service.example            | Production origin must be a bare HTTPS origin                        |
      | /tmp/bnest-deploy | https://service.example/path      | Production origin must be a bare HTTPS origin                        |
      | /tmp/bnest-deploy | https://user@service.example      | Production origin must be a bare HTTPS origin                        |
      | /tmp/bnest-deploy | https://service.example/?query=1  | Production origin must be a bare HTTPS origin                        |
      | /tmp/bnest-deploy | https://service.example/#fragment | Production origin must be a bare HTTPS origin                        |

  Rule: The release builds in a detached worktree the platform service owns

  # Exemption(e2e): the release host's checkout is host state; alternative-proof: bnest-app:test:integration / The release builds in a detached worktree and removes it afterwards, also when the build fails
  @e2e-exempt
  Scenario: The release builds in a detached worktree and removes it afterwards, also when the build fails
    Given a release build records its run calls
    When the build succeeds and when the build throws
    Then both runs add and remove the same detached worktree and the checkout is unchanged

  # The other platforms cannot be observed from this host without injecting
  # code; the host's own platform row is bound below at integration.
  # Exemption(e2e): the platform check runs below every public boundary; alternative-proof: release:test / The release tool picks the service manager for the platform and stops on any other platform
  @e2e-exempt
  Scenario Outline: The release tool picks the service manager for the platform and stops on any other platform
    Given the platform is "<platform>"
    When the service adapter is picked
    Then it uses "<adapter>" or stops with "<message>"

    Examples:
      | platform | adapter | message                                                                                                                |
      | darwin   | launchd | none                                                                                                                   |
      | linux    | systemd | none                                                                                                                   |
      | win32    | (none)  | unsupported platform \"win32\": the release tool supports darwin (launchd) and linux (systemd) only.                   |
      | freebsd  | (none)  | unsupported platform \"freebsd\": the release tool supports darwin (launchd) and linux (systemd) only.                 |

  Rule: The proxy commands install Caddy and report the routed slot

  # Carries BN-CLI-05 (proxy:install): installing the Caddy service writes
  # host state through the platform service manager and needs the real Caddy
  # binary, so no test boundary can run it; the unit suite below is the
  # executable proof.
  # Exemption(integration): proxy:install installs a system service through the platform service manager and needs the real Caddy binary, so no test boundary can run it; alternative-proof: bnest-app:test:unit / proxy:install writes a validated Caddy configuration for the active slot and installs its service
  @integration-exempt
  # Exemption(e2e): proxy:install installs a system service on the host and needs the real Caddy binary (spawnSync caddy ENOENT in CI); alternative-proof: bnest-app:test:unit / proxy:install writes a validated Caddy configuration for the active slot and installs its service
  @e2e-exempt
  Scenario: proxy:install writes a validated Caddy configuration for the active slot and installs its service
    Given the deployment state routes the "blue" slot
    When proxy:install runs with its doubles
    Then it writes the Caddy configuration for the active slot, validates it, and installs its service
    And it leaves "Caddy is managed at 127.0.0.1:4100 for blue." on standard output

  # Carries BN-CLI-05 (proxy:status): the E2E suites drive browser journeys
  # against leased ports and cannot observe the loopback proxy probe; the
  # integration suite runs the real command below.
  # Exemption(e2e): the E2E suites drive browser journeys against leased ports and cannot observe the loopback proxy probe; alternative-proof: bnest-app:test:integration / proxy:status prints the routed slot and revision and exits 1 when Caddy is not ready
  @e2e-exempt
  Scenario: proxy:status prints the routed slot and revision and exits 1 when Caddy is not ready
    Given the deployment state routes the "green" slot at the revision
    When proxy:status runs against a silent Caddy port
    Then it prints the routed slot and revision with caddyReady false and exits 1
