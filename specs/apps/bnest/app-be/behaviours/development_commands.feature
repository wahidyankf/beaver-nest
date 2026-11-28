Feature: Bnest development commands

  Rule: Each server keeps to its own loopback port range

  # Carries BN-DOC-05: the back-end E2E pool 4030 to 4039 is the back-end
  # project's own pool, alongside the front-end E2E 4010 to 4019 row.
  # Exemption(integration): the lease is granted by the pinned HIPPO release, a downloaded binary outside this repository, so no integration boundary of this repository sees a range being granted; alternative-proof: bnest-app:test:unit / Each server keeps to its own loopback port range
  @integration-exempt
  # Exemption(e2e): the E2E harness boots its own servers on its own leased port and cannot observe the dev, slot or Caddy ports of the host; alternative-proof: bnest-app:test:unit / Each server keeps to its own loopback port range
  @e2e-exempt
  Scenario Outline: Each server keeps to its own loopback port range
    Given the "<server>" server is allocated loopback ports <first> to <last>
    When the configured port for "<server>" is <port>
    Then the port stays inside its range and the server binds loopback

    Examples:
      | server           | first | last | port |
      | development      | 4020  | 4029 | 4020 |
      | production blue  | 4000  | 4000 | 4000 |
      | production green | 4001  | 4001 | 4001 |
      | Caddy            | 4100  | 4100 | 4100 |
      | front-end E2E    | 4010  | 4019 | 4010 |
      | back-end E2E     | 4030  | 4039 | 4030 |

  Rule: The start command serves the development app on its loopback port

  # Carries BN-CLI-01 and BN-CFG-02: the BNEST_DEV_PORT row is the CFG-02 half.
  # Exemption(e2e): E2E boots the test profile on its own leased port, never the stable dev profile; alternative-proof: bnest-app:test:integration / npm start serves the development app on its loopback port
  @e2e-exempt
  Scenario Outline: npm start serves the development app on its loopback port
    Given BNEST_DEV_PORT is "<dev-port>"
    When the start command is rendered
    Then the HIPPO lease requests port <port> for owner development from 4020 to 4029
    And the dev endpoint binds "127.0.0.1" on port <port>

    Examples:
      | dev-port | port |
      | (unset)  | 4020 |
      | 4025     | 4025 |

  Rule: Every test command runs its Nx target under a HIPPO admission

  # Carries BN-CLI-02 and BN-CLI-03.
  # Exemption(integration): running the real command re-enters the suite that is running it, and the E2E rows need browsers and booted servers, so no boundary is left to observe; alternative-proof: bnest-app:test:unit / Each npm test command runs its Nx target under a HIPPO admission
  @integration-exempt
  # Exemption(e2e): running the real command re-enters the suite that is running it, and the E2E rows need browsers and booted servers, so no boundary is left to observe; alternative-proof: bnest-app:test:unit / Each npm test command runs its Nx target under a HIPPO admission
  @e2e-exempt
  Scenario Outline: Each npm test command runs its Nx target under a HIPPO admission
    Given the root script "<script>" runs the chain "<chain>"
    When the chain runs with "<failing>" failing
    Then the targets after the failure never run
    And the "<script>" script admits "<admission>"

    Examples:
      | script      | chain              | failing   | admission                                |
      | test        | test:unit          | test:unit | ephemeral standard disk .                |
      | test:live   | test:live          | test:live | ephemeral standard disk .                |
      | test:e2e:be | be-e2e             | be-e2e    | ephemeral standard disk .                |
      | test:e2e:fe | fe-e2e             | fe-e2e    | ephemeral heavy disk .                   |
      | test:e2e    | be-e2e then fe-e2e | be-e2e    | delegates to test:e2e:be and test:e2e:fe |

  Rule: The tailnet commands drive Tailscale Serve for the Caddy port

  # Exemption(e2e): it needs a real tailscaled and a tailnet, which are host state outside any repository or test boundary; alternative-proof: bnest-app:test:integration / The tailnet commands drive Tailscale Serve for the Caddy port
  @e2e-exempt
  Scenario Outline: The tailnet commands drive Tailscale Serve for the Caddy port
    Given the bnest-app target "<target>" declares "<command>"
    When the target runs with a recording tailscale double
    Then the double records "<command>" and the target exits with the double

    Examples:
      | target         | command                                                  |
      | tailnet:up     | tailscale serve --bg --yes --https=443 --set-path=/ 4100 |
      | tailnet:status | tailscale serve status                                   |
      | tailnet:down   | tailscale serve --https=443 --set-path=/ off             |

  Rule: Every Nx target runs the checks it names, in order

  # Carries BN-CLI-27 and BN-GATE-08: the lint, typecheck, format and
  # test:quick rows are the GATE-08 half. The reviewed `test:coverage:behaviour`
  # row is the `test:behaviour:verify` target below: the behaviour check was
  # split into the runner-side verify and the static coverage check, and verify
  # is the Elixir and Vitest binding check the row names.
  # Exemption(integration): running the real targets re-enters the suite that executes them, so there is no boundary left to observe; alternative-proof: bnest-app:test:unit / Each Nx target runs the checks it names, in order
  @integration-exempt
  # Exemption(e2e): running the real targets re-enters the suite that executes them; alternative-proof: bnest-app:test:unit / Each Nx target runs the checks it names, in order
  @e2e-exempt
  Scenario Outline: Each Nx target runs the checks it names, in order
    Given the bnest-app target "<target>" declares "<commands>" with dependsOn "<depends>" and parallel "<parallel>"
    When the target definition is read back
    Then it runs its commands in order

    Examples:
      | target                | commands                                                                                                                                                                                                                                                                                                                                                                                                                                             | depends           | parallel |
      | lint                  | mix format --check-formatted ;; mix credo --strict ;; npm exec -- oxlint --deny correctness --deny suspicious --deny pedantic --deny perf --deny-warnings --report-unused-disable-directives assets/js ;; mix deps.unlock --check-unused                                                                                                                                                                                                                      | (none)            | false    |
      | typecheck             | MIX_ENV=test mix compile --warnings-as-errors --force ;; MIX_ENV=test mix dialyzer --no-compile --format short ;; npm exec -- tsc --project assets/tsconfig.json --noEmit                                                                                                                                                                                                                                                                        | (none)            | false    |
      | format                | mix format --check-formatted                                                                                                                                                                                                                                                                                                                                                                                                                       | (none)            | (none)   |
      | test:quick            | npm exec -- nx run -p bnest-app -t typecheck ;; npm exec -- nx run -p bnest-app -t lint ;; npm exec -- nx run -p bnest-app -t test:unit ;; npm exec -- nx run -p bnest-app -t test:behaviour:verify ;; npm exec -- nx run -p bnest-app -t test:behaviour:coverage                                                                                                                                                                                      | (none)            | false    |
      | test:integration      | BNEST_TEST_LAYER=integration MIX_ENV=test mix do compile --warnings-as-errors + test --warnings-as-errors --exclude integration-exempt --exclude ci-exempt --max-cases 1 test/integration                                                                                                                                                                                                                                                        | test-data:cleanup | (none)   |
      | test:live             | BNEST_TEST_LAYER=integration MIX_ENV=test mix do compile --warnings-as-errors + test --warnings-as-errors --only ci-exempt --max-cases 1 test/integration/bnest_app/codex_chat/live_codex_test.exs                                                                                                                                                                                                                                               | test-data:cleanup | (none)   |
      | test:behaviour:verify | MIX_ENV=test mix run --no-start test/behaviour/verify.exs ;; npm exec -- vitest run test/behaviour/verify.ts --root assets --config vitest.config.mts --testNamePattern \"binding coverage\"                                                                                                                                                                                                                                                        | (none)            | false    |
