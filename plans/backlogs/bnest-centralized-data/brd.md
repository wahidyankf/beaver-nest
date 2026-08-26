# Business Requirements Document

## Business Goal

Make Bnest a private application that requires login and retains its data centrally, per user, without losing existing browser or runtime-folder data.

## Rationale

Browser-only state cannot follow a family member across devices and cannot be safely attributed to an authenticated person. The repository's runtime-data layout also has no Bnest-owned application area. A migration that overwrites those sources would risk losing learning progress or chat context, so preservation is a primary outcome rather than a cleanup task.

## Affected Roles

- **Child:** uses permitted Bnest experiences after login.
- **Parent:** uses permitted household and personal Bnest experiences after login.
- **Admin:** provisions access and validates recovery evidence.
- **Maintainer:** evolves schemas and releases without reading or committing private data.

`children`, `parents`, and `admin` are assignable roles, not mutually exclusive account types. One user may hold any combination. Role capabilities and record ownership remain separate: role assignment alone must not disclose another user's data.

## Required Outcomes

1. No protected Bnest route or data operation succeeds before login.
2. User-owned records are separated by stable user identity.
3. Bnest-wide configuration and content live beneath `data/apps/beaver-nest/`.
4. Repository-wide operational metadata lives beneath `data/system/` and never contains user-authored content or credentials.
5. Existing browser snapshots and legacy files are copied, checksummed, and recoverable before any new representation becomes active.
6. No migration or rollback silently deletes, truncates, or overwrites a source record.

## Success Measures

- An approved user must authenticate before opening Bnest and cannot read another user's records.
- A current browser imports its existing chat and learning snapshots, with source snapshot, import result, and checksum recorded.
- A restart reads the same authenticated user's centralized state from the new layout.
- A deliberately interrupted import resumes or safely reports its state without losing the source snapshot.
- Restore rehearsal recreates imported data from verified backup and migration manifests.

## Non-Goals

- Public registration, public internet exposure, or third-party identity federation.
- Deleting legacy browser storage or `data/general/` as part of the first migration.
- Replacing the current LiveView user experience before equivalent centralized persistence works.
- Storing secrets, credentials, or Git-tracked user data in `data/`.

## Business Risks

| Risk                                         | Mitigation direction                                                                                                |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| A migration loses a browser-only snapshot    | Copy first, retain browser storage, require checksum acknowledgement, and test interrupted imports.                 |
| One user's records become visible to another | Authenticate before import or read; derive all user paths from verified server-side identity.                       |
| Legacy paths are removed prematurely         | Keep them read-only and require explicit archival after backup and restore evidence.                                |
| Login blocks a household member permanently  | Define approved-user bootstrap and recovery before rollout; preserve existing local state until access is restored. |
