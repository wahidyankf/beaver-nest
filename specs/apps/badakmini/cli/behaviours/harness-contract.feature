Feature: Repository coding-harness contract

  Scenario: Canonical instructions skills agents and Nx capability pass
    Given a valid one-skill web-researcher harness contract
    When I inspect the harness contract
    Then harness-contract validation succeeds with 3 harnesses, 1 skill, 1 agent, and 1 capability

  Scenario: Claude imports only the canonical AGENTS file
    Given a valid one-skill web-researcher harness contract
    And the Claude rule adapter contains extra instructions
    When I inspect the harness contract
    Then the harness-contract violations include "invalid-instruction-adapter"

  Scenario: Rule adapter overlays or changed effective content fail
    Given a valid one-skill web-researcher harness contract
    And OpenCode declares an instruction overlay
    When I inspect the harness contract
    Then the harness-contract violations include "unexpected-instruction-source"

  Scenario: Additional or nested instruction sources fail
    Given a valid one-skill web-researcher harness contract
    And a nested repository instruction file exists
    When I inspect the harness contract
    Then the harness-contract violations include "unexpected-instruction-source"

  Scenario: Every canonical skill has exactly one thin Claude adapter
    Given a valid one-skill web-researcher harness contract
    And the canonical skill adapter is missing
    When I inspect the harness contract
    Then the harness-contract violations include "missing-skill-adapter"

  Scenario: Skill descriptions and routes cannot drift
    Given a valid one-skill web-researcher harness contract
    And the canonical skill adapter has a stale description and extra body
    When I inspect the harness contract
    Then the harness-contract violations include "skill-content-divergence"

  Scenario: Skill bodies and supporting resources affect the contract digest
    Given a valid one-skill web-researcher harness contract
    When I inspect and remember the harness contract digest
    And I add a canonical skill supporting resource
    And I inspect the harness contract again
    Then harness-contract validation succeeds
    And the harness contract digest changed

  Scenario: Malformed or duplicated canonical skills fail
    Given a valid one-skill web-researcher harness contract
    And a duplicate canonical skill name exists
    When I inspect the harness contract
    Then the harness-contract violations include "invalid-skill"

  Scenario: Every canonical custom agent has three equivalent adapters
    Given a valid one-skill web-researcher harness contract
    When I inspect the harness contract
    Then harness-contract validation succeeds with 3 harnesses, 1 skill, 1 agent, and 1 capability

  Scenario: Missing stale or extra custom-agent adapters fail
    Given a valid one-skill web-researcher harness contract
    And one canonical agent adapter is missing
    And an unexpected custom-agent adapter exists
    When I inspect the harness contract
    Then the harness-contract violations include "missing-agent-adapter"
    And the harness-contract violations include "unexpected-agent-adapter"

  Scenario: Extra agent prompt content or semantic drift fails
    Given a valid one-skill web-researcher harness contract
    And the Codex agent adapter contains extra prompt instructions
    And the OpenCode agent adapter weakens a denied capability
    When I inspect the harness contract
    Then the harness-contract violations include "agent-prompt-divergence"
    And the harness-contract violations include "agent-semantic-divergence"

  Scenario: Web researcher adapters preserve source and read-only constraints
    Given a valid one-skill web-researcher harness contract
    When I inspect the harness contract
    Then harness-contract validation succeeds

  Scenario: Equivalent Nx MCP declarations pass in all harness configs
    Given a valid one-skill web-researcher harness contract
    When I inspect the harness contract
    Then harness-contract validation succeeds

  Scenario: Divergent or unreadable harness capability config fails closed
    Given a valid one-skill web-researcher harness contract
    And the OpenCode Nx MCP command diverges
    When I inspect the harness contract
    Then the harness-contract violations include "divergent-capability"
    Given a valid one-skill web-researcher harness contract
    And the Claude MCP config is unreadable
    When I inspect the harness contract
    Then the exit code is 2

  Scenario: Inspection excludes generated trees local overrides and links
    Given a valid one-skill web-researcher harness contract
    And excluded instruction sources and a linked skill exist
    When I inspect the harness contract
    Then harness-contract validation succeeds

  Scenario: Findings are stable sorted and inspection is read-only
    Given a valid one-skill web-researcher harness contract
    And two sorted harness-contract violations exist
    And I remember the repository snapshot
    When I inspect the harness contract twice
    Then harness-contract outputs are identical
    And harness-contract violations are ordinally sorted
    And the repository snapshot is unchanged
