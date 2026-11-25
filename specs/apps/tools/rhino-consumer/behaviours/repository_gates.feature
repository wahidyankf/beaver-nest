Feature: Repository gates
  The rhino-consumer project owns which checks run and in what combination.
  It does not own the executable, its command surface, or the policy; every
  value enforced here is declared in repo-config.yml at the repository root.

  # Carries BN-GATE-01: test:repo runs the pre-push surface.
  # Exemption(integration): the pre-push surface is executed by the pinned RHINO release in CI, no integration-globbed file re-enters it; alternative-proof: rhino-consumer:test:repo / The pre-push gate runs the entries repo-config.yml lists for it
  @integration-exempt
  # Exemption(e2e): a repository tool with no application boundary; alternative-proof: rhino-consumer:test:repo / rhino-consumer test:repo runs the pre-push gate surface over the checkout
  @e2e-exempt
  Scenario: rhino-consumer test:repo runs the pre-push gate surface over the checkout
    Given the rhino-consumer test:repo target pipes one synthetic push line into ./rhino gate run
    When the target runs with HEAD and the zero object id for refs/heads/test-repo
    Then ./rhino gate run receives --surface pre-push --push-updates-stdin and the target exits with its status
    And its Nx inputs are the governed content, rhino, rhino.lock and repo-config.yml

  # Carries BN-GATE-02: test:bootstrap runs the RHINO bootstrap proofs.
  # Exemption(integration): the RHINO bootstrap proofs are the whole-file harness binding; alternative-proof: rhino-consumer:test:integration
  @integration-exempt
  # Exemption(e2e): repository tool with no application boundary; alternative-proof: rhino-consumer:test:bootstrap / rhino-consumer test:bootstrap runs the RHINO bootstrap proofs
  @e2e-exempt
  Scenario: rhino-consumer test:bootstrap runs the RHINO bootstrap proofs
    Given the rhino-consumer test:bootstrap target runs .github/scripts/test-rhino-bootstrap.sh
    When the target runs in a workspace
    Then its inputs are rhino, rhino.lock, that script and the RHINO consumer features
    And the real script is the whole-file binding of the bootstrap features, so it is not re-entered here

  # Carries BN-GATE-03: pre-push entries and refusal.
  # Exemption(integration): the surface is executed by the pinned RHINO release, whose engine is tested in its own repository; this repository owns only the declared entries; alternative-proof: rhino-consumer:test:repo / The pre-push gate runs the entries repo-config.yml lists for it
  @integration-exempt
  # Exemption(e2e): repository tool with no application boundary; alternative-proof: rhino-consumer:test:repo / The pre-push gate runs the entries repo-config.yml lists for it
  @e2e-exempt
  Scenario Outline: The pre-push gate runs the entries repo-config.yml lists for it and refuses the push when one fails
    Given the pre-push surface lists "<entry>" with the push range bound for public-safety-range only
    When the hook runs and "<entry>" fails
    Then the hook exits non-zero and the surface receives the push-update lines, not Git's own arguments

    Examples:
      | entry                  |
      | public-safety-tree     |
      | public-safety-range    |
      | remote-dispatch-refusal |
      | repo-config            |
      | word-budget            |
      | directory-map          |
      | quality-gates          |
      | harness-adapters       |
      | internal-links         |
      | mermaid                |

  # Carries BN-GATE-04: PR routing by changed paths.
  # Integration is bound by .github/scripts/test-pr-quality-routing.sh.
  # Exemption(e2e): the gate runs on GitHub-hosted runners with a pull request event; alternative-proof: .github/scripts/test-pr-quality-routing.sh (integration binding)
  @e2e-exempt
  Scenario Outline: The pull-request gate routes the conditional suites by the changed paths
    Given the changed paths include "<path>"
    When the workflow's routing step runs with a git double listing those paths
    Then it sets "<suite>" to "<value>"

    Examples:
      | path                          | suite          | value |
      | .claude/settings.json         | governed       | true  |
      | specs/apps/bnest/app-be/behaviours/chat.feature | governed | true |
      | hippo                         | hippo_consumer | true  |
      | rhino                         | rhino_consumer | true  |
      | .github/workflows/pr-quality-gate.yml | all named | true |
      | apps/bnest-app/src/unrelated.ts | none       | false |

  # Carries BN-GATE-05: scheduled gates timing and order.
  # Exemption(integration): the trigger is GitHub's scheduler, which no local boundary reproduces; alternative-proof: bnest-app:test:unit / The scheduled gates run at 06:00 and 18:00 WIB
  @integration-exempt
  # Exemption(e2e): this workflow runs the E2E suites; alternative-proof: bnest-app:test:unit / The scheduled gates run at 06:00 and 18:00 WIB
  @e2e-exempt
  Scenario: The scheduled gates run at 06:00 and 18:00 WIB with the integration suite before the end-to-end suites
    Given the scheduled-quality-gates workflow declares cron 0 6,18 * * * with timezone Asia/Jakarta
    When the schedule triggers with manual dispatch and serial concurrency without cancellation
    Then it runs test:integration, then the back-end E2E, then the front-end E2E

  # Carries BN-GATE-06: Conventional Commit lint.
  # Integration is bound by scripts/check-commit-message.sh with RHINO_GATE_MESSAGE per row.
  # Exemption(integration): commit lint runs over the PR range in CI via the commit-message gate entry; alternative-proof: scripts/check-commit-message.sh
  @integration-exempt
  # Exemption(e2e): a Git hook with no application boundary; alternative-proof: rhino-consumer:test:repo / A commit message must be a Conventional Commit
  @e2e-exempt
  Scenario Outline: A commit message must be a Conventional Commit
    Given the commit message is "<message>"
    When commitlint lints it with @commitlint/config-conventional
    Then it is "<verdict>" with the commitlint reasons, or RHINO_GATE_MESSAGE is required

    Examples:
      | message              | verdict  |
      | feat: add x          | accepted |
      | fix(scope): y        | accepted |
      | no type here         | refused  |
      | unknowntype: z       | refused  |
      | feat:                | refused  |
      | (missing message)    | refused: RHINO_GATE_MESSAGE is required |

  # Carries BN-GATE-07: behaviour coverage proves adapter completeness.
  # Integration is bound by test/behaviour/verify.exs against a temp corpus holding one unbound scenario.
  # E2E is bound by construction for the E2E adapters: Playwright BDD fails on an undefined step, and
  # check-behaviour-compliance.mts has its own test.
  # Exemption(integration): the corpus proof runs as a whole-file verify; alternative-proof: bnest-app:test:behaviour:verify
  @integration-exempt
  # Exemption(e2e): the bindings-coverage proof runs below every e2e boundary; e2e steps exercise the product while the proof that they cover the corpus is the verify run itself; alternative-proof: bnest-app:test:behaviour:verify / test:coverage:behaviour proves the adapters cover the whole scenario corpus
  @e2e-exempt
  Scenario Outline: test:coverage:behaviour proves the adapters cover the whole scenario corpus
    Given the corpus and bindings are "<state>"
    When test:coverage:behaviour runs
    Then it exits "<status>" and names the unbound scenario when one exists, refusing File, System or non-memory adapters in unit steps

    Examples:
      | state                                          | status |
      | every scenario bound at every required level   | 0      |
      | one scenario without a binding                 | non-zero naming that scenario |
      | a unit step touching File, System or non-memory | refused by the boundary policy |
