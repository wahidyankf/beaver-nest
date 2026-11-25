Feature: Bnest runtime configuration

  Rule: The release port and server flag come from the environment

  # Carries BN-CFG-01.
  # The PORT rows are E2E-bound: the harness boots the release with PORT set to its leased port, and the E2E steps
  # reach the server on that leased port through the health probe.
  Scenario Outline: PORT sets the HTTP port and PHX_SERVER makes the release serve
    Given PORT is "<port-value>" and PHX_SERVER is "<server-value>"
    When the runtime settings are derived
    Then the HTTP port is <port> and the server is "<server>"

    Examples:
      | port-value | server-value | port | server |
      | (unset)    | (unset)      | 4000 | off    |
      | 4101       | (unset)      | 4101 | off    |

  # Carries BN-CFG-01.
  # PHX_SERVER rows cannot be observed from the exact origin the E2E harness
  # boots; the integration adapter proves them.
  # Exemption(e2e): the E2E harness boots its own servers on its own leased port and cannot observe the release PHX_SERVER flag; alternative-proof: bnest-app:test:integration / PHX_SERVER makes the release serve
  @e2e-exempt
  Scenario Outline: PHX_SERVER makes the release serve
    Given PORT is "<port-value>" and PHX_SERVER is "<server-value>"
    When the runtime settings are derived
    Then the HTTP port is <port> and the server is "<server>"

    Examples:
      | port-value | server-value | port | server |
      | (unset)    | true         | 4000 | on     |
      | 4101       | true         | 4101 | on     |

  Rule: Production boot names its secret and host

  # Carries BN-CFG-03.
  # Exemption(e2e): a production-compiled release is not started for exact-origin E2E; alternative-proof: bnest-app:test:integration / Production boot needs SECRET_KEY_BASE and PHX_HOST names the host
  @e2e-exempt
  Scenario Outline: Production boot needs SECRET_KEY_BASE and PHX_HOST names the host
    Given SECRET_KEY_BASE is "<secret>" and PHX_HOST is "<host-value>"
    When the production endpoint is derived
    Then the production boot is "<boot>" with URL host "<url-host>" on 443 and loopback bind

    Examples:
      | secret   | host-value    | boot                                              | url-host       |
      | (unset)  | (unset)       | environment variable SECRET_KEY_BASE is missing. | example.com    |
      | secret-1 | family.example | ok                                                | family.example |
      | secret-1 | (unset)       | ok                                                | example.com    |

  Rule: The flat-file runtime root follows its environment override

  # Carries BN-CFG-04.
  # E2E-bound: the E2E runner sets its run-scoped runtime root and every scenario reads and writes under it; the E2E
  # steps assert that root through the testing-control probe client.
  Scenario Outline: BNEST_RUNTIME_ROOT moves the flat-file runtime root
    Given BNEST_RUNTIME_ROOT is "<raw>"
    When the runtime root is derived with "<cwd>"
    Then the runtime root is "<resolved>"

    Examples:
      | raw         | cwd | resolved          |
      | (unset)     | /srv/bnest | (default)   |
      | /data/other | /srv/bnest | /data/other |
      | relative    | /srv/bnest | /srv/bnest/relative |

  Rule: The Codex directories follow their environment overrides

  # Carries BN-CFG-05.
  # Exemption(e2e): the exact origin cannot repoint the serving checkout or Codex home per row; alternative-proof: bnest-app:test:integration / The Codex working directory and Codex home follow BNEST_CODEX_WORKING_DIRECTORY and BNEST_CODEX_HOME
  @e2e-exempt
  Scenario Outline: The Codex working directory and Codex home follow BNEST_CODEX_WORKING_DIRECTORY and BNEST_CODEX_HOME
    Given BNEST_CODEX_WORKING_DIRECTORY is "<working-raw>" and BNEST_CODEX_HOME is "<home-raw>"
    When the Codex directories are derived
    Then the working directory is "<working>" and the Codex home is "<home>" and repo images come from the working directory and generated images from the home

    Examples:
      | working-raw | home-raw | working   | home     |
      | (unset)     | (unset)  | (default) | (default) |
      | /repo/other | /home/other | /repo/other | /home/other |

  Rule: The Codex runners follow their environment overrides

  # Carries BN-CFG-06.
  # E2E-bound: the e2e servers start with both variables naming the fixture runners, and the chat scenarios observe
  # the fixture replies; the E2E steps assert the pinned fixture runners and observe a fixture reply.
  Scenario Outline: BNEST_CODEX_RUNNER and BNEST_CODEX_MODELS_RUNNER choose the chat and model-discovery runners
    Given BNEST_CODEX_RUNNER is "<runner>" and BNEST_CODEX_MODELS_RUNNER is "<models-runner>"
    When the Codex runners are derived
    Then the chat runner is "<chat>" and the models runner is "<models>" and the test profile selects "<session>"

    Examples:
      | runner   | models-runner | chat     | models   | session  |
      | (unset)  | (unset)       | (bundled) | (bundled) | fixture |
      | /bin/other | /bin/models-other | /bin/other | /bin/models-other | fixture |
      | (fixture) | (fixture)    | (fixture) | (fixture) | real    |

  Rule: Boolean settings accept only true or false

  # Carries BN-CFG-07, BN-CFG-08 and BN-CFG-11.
  # Exemption(e2e): a boot refusal is below every public application boundary; alternative-proof: bnest-app:test:integration / A boolean setting accepts only true or false and otherwise stops the boot
  @e2e-exempt
  Scenario Outline: A boolean setting accepts only true or false and otherwise stops the boot
    Given boolean setting "<name>" is "<value>"
    When the boolean setting is derived
    Then the boolean outcome is "<outcome>"

    Examples:
      | name                      | value   | outcome                                     |
      | BNEST_IDENTITY_CUTOVER    | true    | true                                        |
      | BNEST_IDENTITY_CUTOVER    | false   | false                                       |
      | BNEST_IDENTITY_CUTOVER    | (unset) | false                                       |
      | BNEST_IDENTITY_CUTOVER    | yes     | BNEST_IDENTITY_CUTOVER must be true or false |
      | BNEST_COOKIE_SECURE       | true    | true                                        |
      | BNEST_COOKIE_SECURE       | false   | false                                       |
      | BNEST_COOKIE_SECURE       | (unset) | false                                       |
      | BNEST_COOKIE_SECURE       | yes     | BNEST_COOKIE_SECURE must be true or false   |
