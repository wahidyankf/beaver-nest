# Delivery Plan

## Executor Legend

- `[AI]` — executable by the repository agent within existing authorization and safety boundaries.
- `[HUMAN]` — requires a maintainer decision, credentials, physical action, or external-state authority.

## Preconditions

- [ ] `[AI]` Re-read current Bnest C4, Gherkin, storage keys, and runtime-data rules; record any conflict before implementation.
- [ ] `[HUMAN]` Decide and document approved-user bootstrap, credential recovery, session expiry, and administrator responsibilities.
- [ ] `[HUMAN]` Define the `children`, `parents`, and `admin` capability matrix, multi-role evaluation, and any explicit parent-to-child sharing rules.
- [ ] `[AI]` Inventory all runtime `data/` entries and supported browser snapshot keys without reading private production content into Git or test fixtures.
- [ ] `[HUMAN]` Define backup location, retention, restore operator, and a tested rollback owner.

## Phase 1 — Storage Contract and Safety Harness

- [ ] `[AI]` Define versioned schemas, stable user IDs, Bnest-owned keys, migration manifest, import IDs, and checksum format.
- [ ] `[AI]` Add required BDD scenarios and failing unit, integration, and browser-E2E bindings before implementation.
- [ ] `[AI]` Create ignored placeholders for `data/users/`, `data/apps/beaver-nest/`, and `data/system/`; update the runtime-data convention only if the durable rule changes.
- [ ] `[AI]` Implement server-owned path construction, validation, atomic replacement, lock/concurrency strategy, and structured failure results.
- [ ] `[AI]` Verify malformed paths, malformed JSON, duplicate imports, write interruption, and concurrent access cannot overwrite accepted data.

### Phase 1 Checkpoint

- [ ] `[AI]` Isolated backup, import, read-back, and restore tests pass.
- [ ] `[AI]` No implementation accepts browser-selected paths.

## Phase 2 — Login and Ownership Boundary

- [ ] `[AI]` Add canonical Gherkin for login, logout, unauthenticated route protection, expired session, multi-role evaluation, and user isolation.
- [ ] `[AI]` Implement credential/session handling with server-side identity and protected LiveView routes.
- [ ] `[AI]` Make every user-data read and write derive its path from authenticated identity.
- [ ] `[AI]` Add administrator bootstrap and recovery flow without storing credentials under `data/`.
- [ ] `[AI]` Verify unit, integration, and E2E adapters prove unauthenticated access cannot read or write user state.

### Phase 2 Checkpoint

- [ ] `[AI]` A current Bnest user must log in before protected access.
- [ ] `[AI]` Cross-user reads fail in every adapter.

## Phase 3 — Browser and Legacy Import

- [ ] `[AI]` Add browser export/import support only for approved Bnest storage keys and schema versions.
- [ ] `[AI]` Implement backup and migration-manifest creation before each import, including checksummed user-owned envelopes.
- [ ] `[HUMAN]` Confirm and initiate import from the current browser and any live legacy data source.
- [ ] `[AI]` Re-read centralized data after import and mark it accepted only on checksum and schema success.
- [ ] `[AI]` Copy `data/general/` into Bnest-owned versioned legacy storage before creating normalized records.
- [ ] `[AI]` Retain browser keys and legacy files unchanged; provide status and retry for incomplete imports.

### Phase 3 Checkpoint

- [ ] `[AI]` Successful, duplicate, malformed, and interrupted imports preserve source data.
- [ ] `[AI]` Imports produce deterministic recovery state.

## Phase 4 — Cutover and Recovery Evidence

- [ ] `[AI]` Place centralized reads and writes behind existing chat and learning flows without removing browser compatibility until acknowledged.
- [ ] `[AI]` Add targeted public E2E journeys for login, existing-browser import, centralized continuation, and user isolation.
- [ ] `[AI]` Run a restore rehearsal using the migration manifest and backup on isolated data.
- [ ] `[AI]` Use Playwright MCP with synthetic users and approved fixture storage: log in, import, reload, confirm continuation, log out, then prove a second user cannot read the first user's state; record only safe evidence in this plan.
- [ ] `[AI]` Update C4, Gherkin, app/E2E READMEs, runtime-data guidance, directory maps, and operational documentation to final as-built state.
- [ ] `[AI]` Record architecture-impact assessment and manual public-boundary smoke results in this plan.

### Phase 4 Checkpoint

- [ ] `[AI]` `test:quick`, affected integration and E2E suites, backup/restore rehearsal, and private login smoke pass.
- [ ] `[HUMAN]` Decide whether a later explicit archival plan is needed; do not delete sources in this plan.

## Rollback Rules

- [ ] `[HUMAN]` Stop new centralized writes before a live rollback.
- [ ] `[AI]` Preserve manifests, accepted records, browser keys, and legacy files.
- [ ] `[HUMAN]` Restore live data from the last verified backup or continue from the retained source representation.
- [ ] `[AI]` Record the failure and route reusable learning to specifications, governance, or a new plan before marking this plan done.
