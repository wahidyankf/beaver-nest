# Product Requirements Document

## Product Overview

Extend Bnest with protected family activities, durable shared records, private document processing, and bounded administration while preserving the existing private-access and rapid-development model.

## Personas

- **Family member:** wants private access to shared information and document-assisted activities from approved devices.
- **Family administrator:** wants to control membership and recover failed application workers safely.
- **Maintainer:** wants repeatable tests, releases, backups, and rollback without handling production data manually.

## User Stories

- As a family member, I want my identity recognized so that I see only activities and records I may access.
- As a family member, I want shared records to persist so that another approved device can continue the activity.
- As a family member, I want document progress and failures shown clearly so that I know whether action is required.
- As an administrator, I want fixed recovery actions so that I can restore service without host-level access.
- As a maintainer, I want backup and rollback evidence so that releases do not gamble with family data.

## Product Requirements

1. Protected routes identify the requester and enforce role- and record-level authorization.
2. Shared relational data and document metadata persist outside the source workspace.
3. Original documents, staging files, and accepted outputs use private storage with explicit ownership.
4. Document jobs expose queued, running, complete, and failed states through LiveView updates.
5. Processors accept only a fixed schema and configured executable; browser input cannot select a command.
6. Administrative controls expose only named, audited operations.
7. Releases require compatible migrations, backup evidence, a health check, and a rollback path.

## Proposed Acceptance Criteria

These scenarios describe planned behavior. During delivery, promote affected behavior into the canonical Gherkin corpus before implementation.

```gherkin
Feature: Private family application foundation

  Scenario: Approved family member opens protected content
    Given an approved family member has a valid private identity
    When they open a protected family activity
    Then the application shows only records they are authorized to access

  Scenario: Shared data survives a release
    Given an approved family record exists
    When the application is released and restarted
    Then the same authorized family members can still access the record

  Scenario: Document processing reports a recoverable outcome
    Given an approved family member submits a supported document
    When the allowlisted processor handles the document
    Then the application reports queued, running, and terminal job state
    And a failure does not discard the original document or expose host control

  Scenario: Administrator recovers a failed worker
    Given the document worker has failed
    When an authorized administrator requests the named restart action
    Then the supervised worker becomes healthy
    And the interface exposes no shell or arbitrary process launcher

  Scenario: Maintainer rolls back a faulty release
    Given a verified backup and previous release exist
    When the current release fails its health check
    Then the maintainer can restore the previous release without losing accepted data
```

## Product Scope

In scope: identity, permissions, shared persistence, private documents, job progress, bounded recovery, backup, release, and rollback.

Out of scope: public registration, public internet exposure, arbitrary processors, general host administration, and unrelated redesign of existing chat or learning experiences.

## Product Risks

- Family identity may depend on network-provided signals that are insufficient for record authorization.
- Cross-device persistence introduces concurrency and ownership rules absent from browser-only state.
- Upload limits, supported formats, and retention rules remain unresolved.
- Administrative actions can become dangerous if their allowed operation set expands implicitly.
