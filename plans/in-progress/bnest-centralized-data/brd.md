# Business Requirements Document

## Business Goal

Make Bnest a private application with one-time username/password setup, login, and central per-user data that preserves existing browser/runtime-folder data during migration but leaves no Bnest durable state client-side after verified cutover.

## Rationale

Browser-only state cannot follow a family member across devices and cannot be safely attributed to an authenticated person. The repository's runtime-data layout also has no Bnest-owned application area. A migration that overwrites those sources would risk losing learning progress or chat context, so preservation is a primary outcome rather than a cleanup task.

## Affected Roles

- **Child:** uses permitted Bnest experiences after login.
- **Parent:** uses permitted self-owned Bnest experiences after login; cross-user household sharing is outside this plan.
- **Admin:** is created during initial setup and uses the self-owned capabilities defined for this plan; later account provisioning is out of scope.
- **Maintainer:** evolves schemas and releases without reading or committing private data.

`children`, `parents`, and `admin` are assignable roles, not mutually exclusive account types. One user may hold any combination. Role capabilities and record ownership remain separate: role assignment alone must not disclose another user's data.

## Required Outcomes

1. No protected Bnest route or data operation succeeds before login.
2. User-owned records are separated by stable user identity.
3. Live Bnest-wide configuration and content live beneath `data/prod/apps/beaver-nest/`; repository-wide shared data stays in `data/prod/general/`.
4. Live operational metadata lives beneath `data/prod/system/`; account/session records may contain a username or password hash, but never user-authored content or plaintext credentials.
5. Existing chat, Sifat Allah quiz/progress, and explicit theme browser state, plus legacy files, are copied, checksummed, and recoverable before any new representation becomes active. After server read-back, Bnest clears only its accepted browser keys and persists future changes centrally.
6. The one-time setup UI creates every initial username/password/role account, including an admin, warns that later account/password management is unavailable, and closes public registration permanently.
7. No migration or rollback silently deletes, truncates, or overwrites a source record.
8. Authentication and migration tests use mirrored `data/test/runs/<run-id>/` roots and synthetic identities; they never read, list, reuse, or delete production user state.

## Success Measures

- An approved user must authenticate before opening Bnest and cannot read another user's records.
- A current browser imports chat, learning/quiz, and theme snapshots; an immutable server source, import result, and checksum are recorded before its Bnest client keys are cleared.
- A restart reads the same authenticated user's centralized state from the new layout.
- A deliberately interrupted import resumes or safely reports its state without losing the source snapshot.
- Restore rehearsal recreates imported data from a verified envelope/legacy recovery copy and migration manifest.
- Responsive setup/login verification covers the selected Bnest design on desktop, tablet, and mobile with keyboard and accessibility evidence.
- Every test-created username begins `test-user-`; exact-root cleanup succeeds after the run, and live data remains byte-for-byte untouched.

## Non-Goals

- Public registration, public internet exposure, or third-party identity federation.
- Deleting a browser key before accepted server read-back, or deleting legacy root-level runtime data, as part of the first migration.
- Redesigning unrelated existing LiveView experiences; only setup, login, import, and migration-status surfaces change here.
- Storing plaintext secrets/credentials or Git-tracked user data in `data/`.

## Business Risks

| Risk                                         | Mitigation direction                                                                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| A migration loses a browser-only snapshot    | Copy first, retain it until checksum/read-back passes, then retain immutable server evidence and test interruptions.                |
| One user's records become visible to another | Authenticate before import or read; derive all user paths from verified server-side identity.                                       |
| Legacy paths are removed prematurely         | Keep root-level sources read-only and require explicit archival after recovery-source and restore evidence.                         |
| Lost credentials block a household member    | Warn before irreversible setup and require explicit acceptance; defer recovery to a later plan without rolling back unrelated data. |
| Password is exposed or weakly stored         | Use setup/login UI only, never log plaintext, and store an Argon2id verifier in ignored runtime data.                               |
| A test corrupts or lists a real user         | Boot against a marked `data/test/runs/<run-id>/`; reject `data/prod/` and clean only the exact run.                                 |
