# Linux Service Adapter Follow-Ups

Six small hardening and coverage gaps left in the release tool after it learned to run production on Linux through
systemd user units.
Provenance: recorded 2026-10-24 from the read-only review of the merged Linux deployment change and from its
commit-time notes.

## Problem / Context

- **`ExecStart` is neither quoted nor percent-escaped.** The generated unit breaks on a release path that contains a
  space or a percent sign. Today's paths contain neither.
- **Slot and unit directories take default modes.** They sit under the owner-only deploy root, so nothing is exposed,
  but the modes are not stated in code.
- **`ensureCaddy` skips an existing binary without checking its version.** A stale binary stays in use after the pinned
  version changes.
- **The Linux runbook section reads unit files with `sed` and no guard for a missing unit.** The command fails with an
  unhelpful message on a host that has not been prepared.
- **The launchd side has thin behavioural coverage.** The Caddy plist, `installCaddyService`, `retireSlot` and
  `copyRelease` have no behavioural test. The code is unchanged from before the Linux work and had the same coverage
  then.
- **The Linux change shipped without Gherkin scenarios, bindings or a smoke run.** The repository rules ask for them
  for project behaviour; the change was covered by unit tests of the release tool only.

## Why Now

Not urgent. Production runs on Linux and works. These gaps matter only when a path changes, the Caddy pin moves, or the
launchd path is touched again.

## Prior Art / Precedents

- The Linux deployment change itself, and its review notes, are the source of each item.
- [Restore root and backend e2e snapshot hardening](restore-root-and-be-e2e-snapshot-hardening.md) is a sibling brief
  for the test and cleanup gaps; it does not cover the release tool.

## Proposed Direction (Sketch)

1. Quote and escape `ExecStart`, state the directory modes, and add a version check to `ensureCaddy`, each with a
   failing test first.
2. Add a missing-unit guard to the runbook commands.
3. Add behavioural tests for the launchd paths named above before the next change to them.
4. Decide whether the release tool needs scenarios and a smoke run, or whether the repository rule should say that
   unit tests are enough for deployment tooling.

## Rough Scope & Non-Goals

In scope: the six items above. Out of scope: replacing systemd or launchd, and any change to the blue/green protocol.

## Risks & Open Questions

- Whether a version check should refuse a mismatch or replace the binary.
- Whether scenarios for a deployment tool can run without a second host.

## What Success Looks Like + Promotion Signal

Success: each item is fixed with a failing test first or closed with a reason. A unit path with a space, a Caddy pin
change, or a change to the launchd path promotes the matching item to a plan.
