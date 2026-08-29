# Resource-Aware Development

**Status:** Completed

**Created:** 2026-08-29

**Started:** 2026-08-29

**Completed:** 2026-08-29

**Scope:** Host-pressure observation and bounded shedding for repository-owned development work and managed releases

## Context

The host has restarted under compressor exhaustion while repository development and unrelated desktop work overlapped. Release monitoring already records aggregate evidence, but its CPU and compressor interpretations are too weak for a development-wide safety contract and ordinary Nx work is unguarded.

## Approach

Build one machine-local collector and policy seam, use it from managed release and protected Nx entry points, serialize repository-owned heavy work, and shed only guarded child process groups. Keep production, Caddy, Tailscale, user applications, and transactional recovery outside development shedding.

## Dependencies

- macOS exported memory-pressure, compressor-availability, virtual-memory, swap, CPU-time, and filesystem signals.
- Existing Nx targets, release transaction, port leases, and live-service continuity rules.

## Navigation

- [Business requirements](brd.md)
- [Product requirements](prd.md)
- [Technical design](tech-docs.md)
- [Delivery checklist](delivery.md)
- [Learnings](learnings.md)

## Directory Map

- [`brd.md`](brd.md) — operational goal, roles, outcomes, and risks.
- [`delivery.md`](delivery.md) — ordered implementation and verification checkpoints.
- [`learnings.md`](learnings.md) — safe evidence and decisions captured during delivery.
- [`prd.md`](prd.md) — maintainer stories and executable plan acceptance.
- [`tech-docs.md`](tech-docs.md) — policy, process lifecycle, interfaces, and file impact.
