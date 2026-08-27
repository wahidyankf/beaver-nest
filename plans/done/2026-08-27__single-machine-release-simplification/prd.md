# Product Requirements

## Personas

- **Family user:** accesses Bnest through private HTTPS and may have a connected LiveView.
- **Child player:** may later participate in a multiplayer session whose authoritative state must survive release reconnects.
- **Maintainer:** releases a reviewed `main` revision from the host machine.
- **Development user:** owns one of 5–10 unrelated development workloads that release automation must not interrupt or reconfigure.

## User Stories

- As a family user, I want a release to keep my page usable or recover it automatically so I do not need to reload, re-enter work, or repeat progress.
- As a child player, I want a release to return me automatically to the same game state without missing or repeating a move.
- As a maintainer, I want the release steps and their rollback to be small, observable, and executable on one machine.
- As the host operator, I want the release process to leave only the active backend and deliberate rollback capacity after its bounded drain.
- As an AI operator, I want one revision-bound sequence with structured stage results so routine releases consume little context and cannot skip a gate accidentally.
- As a maintainer, I want multiple daily release requests serialized and coalesced so they do not overlap drains, resources, or rollback state.
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
    Then each model has its own port-labelled diagram
    And each model states its continuity, resource formula, test impact, rollback, WebSocket, migration, and complexity trade-offs
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

  Scenario: An in-progress persisted chat resumes safely
    Given an isolated authenticated chat has a persisted pending turn
    When it reconnects before the turn completes
    Then the chat route remains usable without a server error
    And the pending turn and transcript remain recoverable
    And the deterministic pre-artifact release gate includes this scenario

  Scenario: A multiplayer WebSocket resumes authoritative state
    Given two isolated child players share one synthetic game session
    And each browser knows its last acknowledged event sequence
    When a release interrupts or moves either WebSocket connection
    Then each browser reconnects automatically without a page reload
    And both browsers recover the same game identifier, version, players, turn, and ordered events
    And an action near the interruption is applied exactly once
    And no authoritative game state depends only on the replaced LiveView process

  Scenario: Every runtime owns an unambiguous port
    Given production, candidate, development, test, and E2E processes may share one host
    When an alternative is assessed or a release preflight runs
    Then its Tailnet, proxy, Phoenix, development, and test ports match the documented port contract
    And an unexpected listener or development collision stops before build or process mutation

  Scenario: Resource expectations are measurable
    Given the live machine resource baseline is not available in repository source
    When alternatives are compared
    Then each alternative declares its steady process formula, release peak formula, retained disk shape, and added measurement
    And no unmeasured MB or CPU value is presented as fact
    And Phase 1 rejects a model that causes swap pressure, health degradation, dropped WebSockets, or unbounded disk growth

  Scenario: Releases coexist with development workloads
    Given the 32 GiB 12-core host runs between 5 and 10 development workloads
    And Bnest serves at most 10 connected users across 3 groups
    When a release requests the shared host capacity
    Then preflight reserves the documented RAM, CPU, and disk safety envelope
    And insufficient capacity returns capacity-deferred without stopping or reconfiguring development work
    And gates run sequentially with bounded schedulers and one browser worker

  Scenario: Multiple daily releases remain serialized
    Given one release transaction owns the host-wide release lock
    When one or more newer revisions request release
    Then no second transaction mutates migration, slots, route, drain, or cleanup state
    And queued requests may coalesce to the newest clean main revision
    And the pinned revision of the running transaction never changes
    And the next activation waits for resolved routing, rollback capacity, drain, and cleanup

  Scenario: A future schema change preserves rollback
    Given an artifact declares a flat-file or database migration
    When the release reaches migration proof
    Then one lock-owned idempotent coordinator expands, migrates, and verifies the data state
    And the active and rollback revisions remain compatible with the expanded state
    And candidate promotion is blocked by missing backup, checksum, lock, compatibility, or restore evidence
    And destructive contract work remains a separate later authorization

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

The acceptance criteria govern the plan assessment only. Application behavior, data schemas, routes, ports, and user interface are unchanged. The multiplayer and database clauses are forward compatibility requirements, not approval to build either feature.

## Risks

The isolated browser gates reconnect LiveView without page reload and preserve route, draft, conversation, and session across desktop, tablet, mobile, and a ten-client/three-group load. The authenticated integration gate also restores a persisted pending chat turn before completion. Development leases the host-safe `4020`–`4029` pool. The release controller pins clean `main`, runs fixed uncached gates before build, produces artifact and migration manifests, owns the release lock, and refuses any non-empty migration set until an approved adapter exists. The repaired managed production release proved the admitted transaction, exact routed revision, anonymous routed LiveView recovery, bounded cleanup, retained cold rollback capacity, and the fixed persisted-pending-turn gate before promotion.
