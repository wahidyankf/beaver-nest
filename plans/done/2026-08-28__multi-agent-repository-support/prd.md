# Product Requirements

## Personas

- **Contributor switching harnesses:** wants repository rules and workflows to remain stable when changing tools.
- **Maintainer changing agent guidance:** wants one canonical edit and an immediate deterministic drift finding for forgotten adapters.
- **Reviewer:** wants machine-readable proof that support is structural rather than a best-effort documentation claim.

## Stories

- As a contributor, I can start Codex, Claude Code, or OpenCode at the repository root and reach the same canonical instructions.
- As a contributor, I can invoke each repository-local skill from every supported harness without maintaining three skill bodies.
- As a contributor, I can use the Nx MCP-dependent workflows and the CI monitor through equivalent declared capabilities.
- As a contributor, I can delegate current or uncertain facts to the same read-only, source-grounded web-research workflow from any supported harness.
- As a maintainer, I can run one Badakmini validator to find parity drift without invoking any harness.
- As a reviewer, I can distinguish guaranteed repository parity from intentionally local or vendor-specific behavior.

## Acceptance Criteria

- **AC-01 — Canonical instructions:** `AGENTS.md` is the only canonical repository rule body; Codex and OpenCode consume those normalized bytes directly, while Claude imports exactly that file with no before/after content or additional always-on rule source.
- **AC-02 — Canonical skills:** `.agents/skills/` owns every complete skill bundle, including `SKILL.md` and supporting resources; each harness resolves the same normalized bundle content, and wrappers may contain only the matching description and exact canonical route.
- **AC-03 — Canonical custom agents:** `.agents/agents/` owns each complete prompt body and semantic contract; the initial set is exactly `ci-monitor-subagent` and `web-researcher`, and every harness adapter must resolve the same prompt, description, mode, capabilities, denies, and constraints without extra workflow instructions.
- **AC-04 — Required capabilities:** each harness declares the same repository-required `nx-mcp` command without credentials or absolute paths.
- **AC-05 — Deterministic validation:** Badakmini normalizes content, builds logical contract records, computes stable SHA-256 content digests, compares harness projections field by field, emits stable text and JSON findings, and returns `0` for parity, `1` for findings, and `2` for invocation or unreadable-config errors.
- **AC-06 — Gate integration:** the focused validator, `test:repo`, Badakmini quality gates, and affected pre-push selection cover all contract paths.
- **AC-07 — Honest boundary:** docs exclude models, provider auth, user-global settings, ignored local memory, and proprietary approval behavior from the parity claim.

## Plan-Level Gherkin

```gherkin
Feature: Work through any supported coding harness

  Scenario Outline: A harness reaches the canonical repository contract
    Given the committed multi-harness contract is valid
    When a contributor starts <harness> at the repository root
    Then the harness receives the canonical AGENTS.md rules
    And every canonical repository skill is available through its declared route
    And the nx-mcp capability and both canonical agent routes are declared

    Examples:
      | harness     |
      | Codex       |
      | Claude Code |
      | OpenCode    |

  Scenario: Claude-specific rule drift is rejected
    Given CLAUDE.md adds a project rule beyond the AGENTS.md import
    When Badakmini validates the harness contract
    Then validation fails with the divergent adapter path

  Scenario: A missing skill adapter is rejected
    Given a canonical skill has no required Claude adapter
    When Badakmini validates the harness contract
    Then validation fails with the skill name and missing adapter path

  Scenario: An adapter changes effective skill content
    Given a Claude skill wrapper changes the canonical description or adds workflow instructions
    When Badakmini validates the harness contract
    Then validation fails with the changed field and both related paths

  Scenario: An agent adapter changes effective behavior
    Given an agent adapter adds prompt content or weakens a canonical deny
    When Badakmini validates the harness contract
    Then validation fails with the agent, harness, and divergent semantic field

  Scenario: The web researcher has one source-quality contract
    Given web-researcher is declared for every supported harness
    When Badakmini validates the harness contract
    Then every adapter routes to the same canonical workflow
    And each adapter routes the canonical repository-read and web-research requirements
    And each adapter declares the strongest native read-only restriction

  Scenario: Capability drift is rejected without starting a harness
    Given one harness declares a different nx-mcp command
    When Badakmini validates the harness contract
    Then validation fails without network, model, or process execution
```

These scenarios accept the plan. The durable Badakmini scenarios selected for implementation are detailed in [Specification Changes](tech-docs.md#specification-changes).

## Risks and Responses

- **Vendor format drift:** keep parsers limited to the exact committed subset and update primary-source evidence before changing adapters.
- **False equality claim:** name the guarantee “repository-owned contract parity,” not complete harness parity.
- **Wrapper duplication:** wrappers may repeat only machine-readable identity/description fields and a fixed route to canonical content.
- **Disabled project settings:** document a fail-closed startup check; Badakmini cannot inspect user runtime choices.
