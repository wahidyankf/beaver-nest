# Technical Documentation

This document proposes a target for [Bnest Centralized Data](README.md). It is not an as-built architecture. Delivery must update the canonical [Bnest C4 model](../../../specs/apps/bnest/app/architecture.md) and executable Gherkin before production code changes.

## Proposed Architecture

Keep Phoenix LiveView as the public boundary. Add an authentication/session boundary and a server-side repository module that owns identity-derived paths, schema validation, atomic writes, import manifests, and backups. The browser exports only known Bnest storage keys; it never receives arbitrary filesystem access.

```text
authenticated browser
  → Phoenix LiveView import event
  → authenticated identity and authorization
  → Bnest data repository
  → data/users/<user-id>/ or data/apps/beaver-nest/
```

`data/system/` is adjacent operational state only. It records manifests and hashes, not user payloads.

## Storage Layout and Ownership

| Location                 | Owner                  | Permitted content                                                                                    |
| ------------------------ | ---------------------- | ---------------------------------------------------------------------------------------------------- |
| `data/users/<user-id>/`  | One authenticated user | Versioned user records, imported browser envelopes, and user-local migration receipts.               |
| `data/apps/beaver-nest/` | Bnest application      | Bnest-wide configuration and shared application data; copied legacy `data/general/` source material. |
| `data/system/`           | Repository/system      | Schema registry, migration manifests, integrity hashes, and non-sensitive operational state.         |

The requested fourth layout position is `data/apps/`, which groups application namespaces. It has no unrelated payload of its own.

Use UTF-8 JSON with explicit schema versions, canonical serialization for checksums, and write-to-temp then atomic replace. All paths are constructed from server-controlled constants and verified user IDs.

## Migration Mechanics

1. Inventory existing `data/` files and recognized browser keys (`bnest.chat.v1`, `bnest.sifat-allah.v1`, and approved future keys) without mutation.
2. Create a dated, checksummed backup and system manifest before copying any record.
3. After login, import browser snapshots into a user-owned envelope containing the original key, raw payload, source schema, hash, import ID, and outcome. Keep the browser key untouched.
4. Copy legacy `data/general/` entries into versioned Bnest-owned legacy storage; validate hashes before creating normalized application records.
5. Read the centralized representation back through the normal application flow before marking an import accepted.
6. Keep the original browser and legacy sources available. Any archival or deletion requires a separate explicit decision, successful restore rehearsal, and a compatibility sunset plan.

## Authentication and Authorization

Select and document a credential/bootstrap/recovery design before implementation, coordinated with the family-app foundation plan. The minimum implementation boundary is server-verified session identity, password hashes rather than credentials in `data/`, logout, session expiry, protected routes, and authorization checks at every repository operation.

Represent role assignments as a set per authenticated user, allowing any combination of `children`, `parents`, and `admin`. Keep role capability checks separate from ownership and sharing checks. Before delivery, define the capability matrix for each action and any parent-to-child sharing policy; default-deny cross-user access until that policy exists.

## File Impact

| Area                       | Expected change                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| `specs/apps/bnest/app/`    | C4 and Gherkin for login, ownership, imports, persistence, failure, and recovery.                       |
| `apps/bnest-app/`          | Authentication, LiveView guards, data repository, schemas, browser import hooks, and migration tooling. |
| `apps/bnest-app-e2e/`      | Login and browser-import journeys with isolated test data.                                              |
| `data/`                    | Ignored placeholders for the new layout; runtime data remains untracked.                                |
| README and governance docs | Current storage, operation, privacy, backup, and recovery guidance.                                     |

## Testing and Rollback

- Unit-test path derivation, authorization, schemas, checksums, atomic replacement, idempotency, and malformed snapshots.
- Integration-test isolated filesystem import, duplicate import, interrupted writes, restore, and legacy-copy validation without network access.
- E2E-test login gating and a browser containing the current storage keys.
- Before each migration stage, make a backup, record manifest and hashes, run the import, re-read central data, and rehearse restore.
- Roll back by disabling new writes and reading the retained source/last accepted record. Never delete source data to make a rollback appear clean.

## Technical Risks

- Browser `sessionStorage` is tab-scoped and may disappear before import; communicate this and import from the browser while available.
- Authentication design remains a prerequisite, not an implementation detail.
- Flat files require process-safe atomicity and clear ownership if concurrent sessions are introduced.
- Legacy data may not match a known schema; preserve it as an opaque envelope and report validation failure rather than coercing or discarding it.
