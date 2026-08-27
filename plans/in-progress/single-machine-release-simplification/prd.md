# Product Requirements

## Personas

- **Family user:** accesses Bnest through private HTTPS and may have a connected LiveView.
- **Maintainer:** releases a reviewed `main` revision from the host machine.

## User Stories

- As a family user, I want a release to keep my page usable or recover it automatically so I do not need to reload, re-enter work, or repeat progress.
- As a maintainer, I want the release steps and their rollback to be small, observable, and executable on one machine.
- As the host operator, I want the release process to leave only the active backend and deliberate rollback capacity after its bounded drain.
- As an AI operator, I want one revision-bound sequence with structured stage results so routine releases consume little context and cannot skip a gate accidentally.
- As a plan reader, I want Mermaid labels checked before push so a clipped transition cannot hide a release condition.

## Acceptance Criteria for This Assessment

```gherkin
Feature: Assess the Bnest single-machine release process

  Scenario: Record the current release condition
    Given the current repository source and governance are available
    When the assessment is created
    Then it records the route, slot lifecycle, readiness evidence, rollback path, and runtime-observation gap
    And it does not claim that the live service was checked when required machine-local configuration is unavailable

  Scenario: Present alternatives and an explicit recommendation
    Given the maintainer wants simpler one-machine releases
    When possible operating models are compared
    Then each model states its continuity, resource, rollback, and complexity trade-offs
    And Caddy is treated as optional rather than a fixed architecture requirement
    And the plan recommends ephemeral blue-green Caddy promotion through one deterministic release transaction
    And the recommendation remains distinct from implementation approval

  Scenario: A connected page survives a release
    Given a family user is interacting with a connected Bnest page
    And the page contains acknowledged or in-progress user work
    When a compatible release is promoted
    Then the page remains usable or reconnects and updates itself automatically
    And the user is not asked to reload the page
    And the current route and user progress are preserved without duplicate actions

  Scenario: A brief release interruption recovers without user action
    Given a family user has a Bnest page open during a release
    When the release briefly interrupts the page connection
    Then the browser restores a usable current page automatically
    And acknowledged data, recoverable in-progress input, and completed progress are unchanged
    And the user does not need to reload, re-enter input, or repeat completed work

  Scenario: Tests pass before an artifact is created
    Given one clean main revision is selected for release
    When the deterministic release pipeline starts
    Then it runs the declared preflight and test gates in a fixed order for that revision
    And a failed or indeterminate gate stops the pipeline before artifact creation
    And the revision cannot change between gate evidence and the artifact

  Scenario: Release stages produce deterministic evidence
    Given every routine release stage has declared inputs and expected outputs
    When a stage completes or fails
    Then it emits a concise machine-readable status with the revision and next valid transition
    And detailed logs remain available outside the AI summary without exposing prohibited data
    And retrying the same stage is idempotent or refuses with a precise recovery action

  Scenario: Mermaid release diagrams reject labels that can become unreadable
    Given changed Markdown contains a supported Mermaid diagram
    When a visible label segment exceeds its repository limit
    Then Badakmini reports the path, line, label role, actual length, and limit deterministically
    And the pre-push repository gate rejects the change
    And explicit line-break segments within the limit remain valid
```

## Scope

The acceptance criteria govern the plan assessment only. Application behavior, data schemas, routes, and user interface are unchanged.

## Risks

The current browser test step that models deployment reconnect uses a page reload, whereas the runtime contract requires automatic recovery without user action and no progress loss. A later assessment checkpoint must inventory recoverable state for each affected journey and inspect the actual routed WebSocket proof before accepting any simplification. The current release builder does not invoke quality gates, verify a clean `main`, or produce an artifact manifest, so deterministic orchestration remains proposed rather than as-built.
