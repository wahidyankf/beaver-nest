# Bnest Post-Closure Follow-Ups

Five small product, governance and cleanup decisions that the `ddd-hexagonal-adoption` plan found and deliberately did not take,
because that plan was a structural refactor with no behaviour change.
Provenance: recorded 2026-10-03 at the archival of `ddd-hexagonal-adoption`, from its `learnings.md` entries E6, E13
and E16.

## Problem / Context

- **`mix bnest.storage.retire` cannot retire after an in-place activation.** It requires `--generation`, but a
  pointer activated in place and never relocated has no `databaseGeneration`, so the task always answers
  `:generation_mismatch`. The backend e2e step reaches the same code through `Storage.retire/3`.
- **The `"fixture"` family task still ships in production configuration.** The base registry carried it. Moving it
  to test configuration is safe only if no production schedule row names `fixture` as its handler, because the
  Scheduler could otherwise not resolve that row. That needs a read-only look at the production schedule table, which
  the owner has not approved.
- **Low findings from the closure review, all older than the plan.** Malformed JSON to `/api/graphql` returns an HTML
  400 although the pipeline documents a JSON envelope. An unauthenticated `PUT /preferences/theme` redirects to a
  `return_to` that a GET cannot serve. No integration test pins the Web Push operations or the socket handshake.
  `/admin/settings/schedules` crashes on a root with no backup schedule row. The theme toggle overlaps the admin
  breadcrumb at 320 px, some inline targets are under 24 px, the login form is four tab stops in and drops focus after
  a rejected login, most page titles are identical, and the `dark` theme leaves the page surfaces light.
- **`AGENTS.md` and the enforcement map cannot name the hexagonal standard.** `AGENTS.md` sits at about 749 of its 750
  counted words and `software-quality-enforcement.md` at 748, and the counter includes link paths. The standard is
  reachable through the skill, the agents and the adapter standard, but not from the two entry points.
- **Backups for the nights of 30 September and 1 October are missing.** This is an investigation, not a finding: the
  admin Schedules page, the schedule and run state and the slot logs have not been read for it.

## Why Now

Not urgent. The household sees none of these as an outage, and each is independent. They are written down together so
that none is lost with the archived plan.

## Prior Art / Precedents

- [Upstream tool defects](../../../repo-governance/development/upstream-tool-defects.md) does not apply: every item is
  in this repository's own code or configuration.
- The closure review that found them is recorded in the archived plan's `learnings.md`, entry E16.

## Proposed Direction (Sketch)

1. Decide whether `storage.retire` should accept a pointer without a generation, or whether in-place activation
   should record one; then change the task and its e2e step together.
2. With the owner's approval, read the production schedule table once and read-only. If no row names `fixture`, move
   the task to test configuration.
3. Group the Low findings by surface (API envelope, authentication redirect, admin page, accessibility) and open one
   plan per surface when the owner picks one up.
4. Investigate the two missing backups read-only before any change to the production schedule.
   Promoted on 2026-10-03 to the formal plan
   [`backup-integrity`](../../in-progress/backup-integrity/README.md); remove this item when that plan is archived.
5. Decide which counted rule to trim, or whether the word budget should change, so the entry points can link the
   standard.

## Rough Scope & Non-Goals

In scope: the five items above. Out of scope: any production data change without the owner's explicit approval,
and any change to the architecture the archived plan established.

## Risks & Open Questions

- Whether the missing backups come from the schedule, the run, or the host is unknown.
- Item 1 changes a Mix task contract that the e2e harness also uses.

## What Success Looks Like + Promotion Signal

Success: each item is either fixed with a failing test first or closed with a reason. The first of these to cause a
visible failure, or the owner's go-ahead for the read-only production check, promotes the matching item to a plan.
