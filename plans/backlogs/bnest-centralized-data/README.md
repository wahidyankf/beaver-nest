# Bnest Centralized Data

**Status:** Backlog  
**Created:** 2026-08-26  
**Scope:** Bnest application, browser-persisted state, and ignored local runtime data

## Context

Bnest currently has no authentication or server-side application data. Chat state stays in the current tab's `sessionStorage`; Sifat Allah progress stays in browser `localStorage`; `data/` contains only ignored placeholders. This plan introduces authenticated, centralized flat-file persistence without discarding the browser or filesystem data that already exists.

The canonical as-built system remains the [Bnest C4 architecture specification](../../../specs/apps/bnest/app/architecture.md). This proposal becomes authoritative only when implemented with its required specification updates.

## Scope

- Require login before any user with access can use Bnest.
- Classify each user with one or more of `children`, `parents`, and `admin` roles.
- Import existing Bnest browser snapshots after authentication and preserve their source copies.
- Store user-owned, application-wide, and system-wide runtime data in the requested `data/` layout.
- Migrate any legacy `data/general/` content by copy, validation, and explicit archival—not destructive replacement.
- Establish backup, restore, and rollback evidence for every migration step.

## Approach Summary

Add an authenticated persistence boundary behind the existing LiveView and browser flows. Keep browser state and legacy flat files intact while importing versioned, checksummed copies into the new layout. Do not clear browser storage or delete legacy files automatically; a later explicit, verified archival decision is required.

The requested four directory positions are `data/users/`, `data/apps/`, `data/apps/beaver-nest/`, and `data/system/`; the direct children of `data/` are therefore `users/`, `apps/`, and `system/`.

## Dependencies

This plan depends on a resolved Bnest identity and session design, including bootstrap administration, credential recovery, and a capability matrix for multi-role users.

## Plan Documents

- [BRD](brd.md) defines the business outcome and data-safety rationale.
- [PRD](prd.md) defines personas, login, migration, and persistence requirements.
- [Technical documentation](tech-docs.md) defines the proposed flat-file layout and migration mechanics.
- [Delivery plan](delivery.md) contains ordered execution and verification gates.
- [Learnings](learnings.md) records transient delivery observations awaiting disposition.

## Directory Map

- [Business requirements](brd.md) owns business goals, outcomes, and risks.
- [Delivery](delivery.md) owns ordered execution, migration gates, and rollback evidence.
- [Learnings](learnings.md) records temporary findings for later disposition.
- [Product requirements](prd.md) owns user-facing requirements and acceptance criteria.
- [Technical documentation](tech-docs.md) owns proposed architecture, data layout, and mechanics.
