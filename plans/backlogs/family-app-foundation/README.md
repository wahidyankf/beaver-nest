# Family App Foundation

**Status:** Backlog  
**Created:** 2026-08-20  
**Scope:** Bnest application, its shared specification corpus, and its browser E2E adapter

## Context

Beaver Nest currently provides local Codex chat and browser-persisted learning experiences through Phoenix LiveView. This plan develops that foundation into a private family application with authenticated access, durable shared data, recoverable document processing, backups, and repeatable releases.

The canonical as-built model is the [Bnest C4 architecture specification](../../../specs/apps/bnest/app/architecture.md). Nothing in this plan overrides it; proposed behavior and architecture become current only after implementation and synchronized specification updates.

## Scope

- Family identity and application-level permissions.
- Durable relational data and private document storage outside the source workspace.
- Allowlisted document jobs with visible, recoverable state.
- Backup, release, health-check, and rollback paths.
- Private HTTPS whose lifecycle remains independent from the application process.

Public internet exposure and arbitrary browser-driven host control remain out of scope.

## Approach Summary

Deliver the foundation as recoverable vertical slices: identity, persistence, document processing, then operations. Each slice begins with affected C4 and Gherkin, follows the repository red–green workflow, and must remain independently releasable or reversible.

The proposed technical direction uses Phoenix LiveView, Elixir/OTP supervision, private Postgres and document volumes, allowlisted processors, Playwright for critical browser journeys, and Tailscale Serve for private HTTPS.

## Dependencies

Execution requires decisions about family identities, first shared records, supported document formats, backup location and retention, and the always-on host. Record resolved decisions in the responsible plan document before the dependent phase starts.

## Plan Documents

- [BRD](brd.md) explains the business goal, outcomes, boundaries, and risks.
- [PRD](prd.md) defines personas, user stories, requirements, and proposed acceptance criteria.
- [Technical documentation](tech-docs.md) describes the proposed architecture, testing, file impact, and rollback.
- [Delivery plan](delivery.md) is the executable phased checklist and verification record.
- [Learnings](learnings.md) is the transient execution log awaiting permanent disposition.

## Directory Map

- [Business requirements](brd.md) owns the plan's business rationale and outcomes.
- [Delivery](delivery.md) owns ordered execution tasks and gates.
- [Learnings](learnings.md) captures transient observations during execution.
- [Product requirements](prd.md) owns product behavior and acceptance criteria.
- [Technical documentation](tech-docs.md) owns proposed design and implementation mechanics.
