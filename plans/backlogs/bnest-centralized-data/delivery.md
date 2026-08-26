# Delivery Plan

## How to Execute This Checklist

- `[AI]` is the default executor: repository discovery, code, tests, documentation, browser automation, and safe evidence are agent work.
- `[HUMAN]` is reserved for live credentials/browser confirmation, production write authority, or a product/archival decision the agent cannot own.
- Every task cites PRD acceptance criteria and names its input, action, observable result, and proof. Tick it and record safe evidence immediately after it passes.
- Follow [plan execution](../../../repo-governance/workflows/plan-execution.md): move this plan to `in-progress` first, stop at every checkpoint, capture learnings, and do not skip red BDD bindings.

## Acceptance Traceability

- `[AC-01]` protected login; `[AC-02]` safe browser copy; `[AC-03]` user isolation; `[AC-04]` multi-role plus ownership.
- `[AC-05]` recoverable interruption; `[AC-06]` persistent browser login; `[AC-07]` independent simultaneous browsers.
- `[AC-08]` verified cutover off client persistence; `[AC-09]` one-time account setup; `[AC-10]` Argon2id without plaintext.
- `[AC-11]` synthetic marked tests that cannot mutate real data.

## Phase 0 — Reconcile Plan and Establish Red Behavior

- [ ] `[AI] [AC-01–AC-11]` Run the plan quality gate against the moved `in-progress` folder. Re-read current C4, all Bnest Gherkin, current browser-storage readers/writers, resolved Nx targets, and every path in [File Impact](tech-docs/file-impact.md). Update the plan for repository drift; proof is a finding log with no unresolved design or path.
- [ ] `[HUMAN] [AC-09]` Accept or reject this exact account-lifecycle boundary before specification edits: setup creates every initial account once; this plan has no later account creation, role edit, disablement, or password recovery; a lost credential leaves only that account unavailable; restoring a migration recovery source will not roll back unrelated data for password recovery. Rejection stops execution and requires plan/UI revision.
- [ ] `[AI] [AC-01–AC-11]` Confirm the implementation uses only the decisions in [technical documentation](tech-docs/README.md), record shapes in [data contracts](tech-docs/data-contracts.md), transition states in [migration design](tech-docs/migration-design.md), and selected [UI design](tech-docs/ui-design.md). Remove any delivery task that would add speculative account management, sharing, all-session revocation, or archival.
- [ ] `[AI] [AC-01–AC-04, AC-06–AC-10]` Apply every selected C4/Gherkin delta in [planned specification changes](tech-docs/specification-changes.md), update specification READMEs, and change no plan-only PRD criterion into a canonical scenario. Proof is a reviewed specification diff with exact scenario names.
- [ ] `[AI] [AC-01–AC-04, AC-06–AC-10]` Create or update every unit, integration, and E2E binding named in [planned specification changes](tech-docs/specification-changes.md). Run `npm exec -- nx run -p bnest-app -t test:coverage:behaviour`; expected result is bindings discovered in every applicable adapter and failures caused only by missing implementation, not undefined steps.
- [ ] `[AI] [AC-01–AC-11]` Record the red target output by target/test name only—no payload, private path, username, cookie, verifier, or production identifier—and mark which implementation phase will turn each failure green.

### Phase 0 Checkpoint

- [ ] `[AI] [AC-01–AC-11]` Re-read the phase from its first item. Confirm every selected behavior has a red binding, every plan-only outcome has a named delivery proof, C4 describes the proposed boundary without claiming as-built completion, and no implementation file changed yet.

## Phase 1 — Runtime Root, Contracts, and Test Safety

- [ ] `[AI] [AC-02, AC-05, AC-08, AC-11]` Add only the tracked placeholders and ignore rules listed in [Ignored Runtime Records](tech-docs/file-impact.md#ignored-runtime-records). Verify root-level legacy sources remain byte-for-byte untouched and generated `data/prod`/`data/test` records stay ignored.
- [ ] `[AI] [AC-03, AC-11]` Implement `test/support/test_runtime_root.ex` first. It must generate one run ID, create only `data/test/runs/<run-id>/`, write the exact marker contract, reject symlinks/shared roots/`data/prod`, and expose cleanup only after registered server/browser processes stop. Unit-test every rejection before using the helper elsewhere.
- [ ] `[AI] [AC-11]` Implement `test/support/test_identity.ex` on top of the proven run helper. Generate only `test-user-<suite>-<run-id>` usernames and synthetic passwords/payloads; assert its account index and family list resolve inside the same run. Never accept a caller-supplied real username or production record.
- [ ] `[AI] [AC-02–AC-05, AC-08, AC-11]` Implement `data_repository/schema.ex` for every record and enum in [data contracts](tech-docs/data-contracts.md). Add focused unit cases for valid examples, missing/extra sensitive fields, wrong types, unsupported versions, invalid IDs, source limits, and safe error categories.
- [ ] `[AI] [AC-02, AC-03, AC-05, AC-07, AC-08, AC-11]` Implement `data_repository/store.ex`: resolve the configured root once, derive paths only from typed server IDs, reject traversal/symlinks, compare `expected_revision` under one per-path lock, write/flush a sibling temp file, atomically replace, then re-read. Test same-revision races and prove a stale/failed candidate leaves the newer accepted file unchanged.
- [ ] `[AI] [AC-11]` Add `bnest-app:schema:audit` and its Mix task. Test that it compares only record type/version/top-level field names/value types, cannot write/authenticate/copy/repair, and never outputs identity-bearing paths, counts, hashes, verifiers, sessions, nested payload fields, or values.
- [ ] `[AI] [AC-11]` Wire `config/runtime.exs`, `config/test.exs`, `application.ex`, and Playwright support to require one root before startup. Start an isolated Bnest process, prove the configured root in the UI/test harness before bootstrap, stop it, validate the marker again, and remove only that exact run. Cleanup failure must fail the target.

### Phase 1 Checkpoint

- [ ] `[AI] [AC-02–AC-05, AC-08, AC-11]` Run focused unit/integration tests for schemas, root derivation, traversal, locks, atomic failure, marker validation, production rejection, and exact cleanup. Inspect safe output and confirm no root-level legacy source or `data/prod` file changed.
- [ ] `[AI] [AC-11]` Run `npm exec -- nx run -p bnest-app -t schema:audit` against one synthetic mirror and read-only production structure. Record only public record-type/version pass/fail categories and before/after proof that production bytes are unchanged.
- [ ] `[AI] [AC-01–AC-11]` Re-read Phase 1 from the first item. Do not begin identity work until all later filesystem tests are forced through the marked helper and every data contract has executable validation.

## Phase 2 — One-time Identity and Session Boundary

- [ ] `[AI] [AC-09, AC-10]` Add and lock a maintained Argon2id library. Benchmark the documented 19 MiB/two-iteration/one-lane baseline on deployment-equivalent hardware through an Nx-invoked task; record only parameters and timing class, then configure the accepted non-secret values.
- [ ] `[AI] [AC-09, AC-10]` Implement username normalization and `identity/file_store.ex` against the account/index/bootstrap contracts. Test username 1/32 boundaries, invalid separators, case-insensitive duplicates, password 15/128 boundaries with Unicode/whitespace/no truncation, role sets, one-admin requirement, and absence of plaintext in files/logs/rendered errors.
- [ ] `[AI] [AC-09, AC-10]` Implement `identity/bootstrap.ex` as one global locked journaled transaction: write a pending `bootstrap.json` with the exact generated IDs/checksums, write and verify accounts/indexes, then atomically mark it closed. On startup, complete or roll back only a matching pending attempt. Test crash recovery and that a closed marker prevents reopening even if an account is later missing.
- [ ] `[AI] [AC-01, AC-06, AC-07, AC-10]` Implement `identity/session.ex`: generate at least 32 random bytes, derive its SHA-256 digest for filename/record, compare safely, persist no raw token, and revoke only the presented digest. Broadcast a digest-specific LiveView disconnect on logout. Test reload/restart lookup, multiple tabs, two browser records, browser-A logout, invalid/revoked token, and absence of server-side expiry.
- [ ] `[AI] [AC-03, AC-04]` Implement the exact capability table in `identity/authorization.ex`. Test each role and multi-role union for own chat/learning/theme/import/status, plus default denial for every cross-user operation and all out-of-scope administration/sharing actions.
- [ ] `[AI] [AC-01, AC-03, AC-06, AC-07]` Implement `user_auth.ex`, `session_controller.ex`, and protected router/live-session boundaries. Set the opaque cookie through the HTTP controller with `HttpOnly` and `SameSite=Lax`; require `Secure` in production HTTPS and allow its test-only localhost override. Sanitize the post-login return path to an internal route.
- [ ] `[AI] [AC-09, AC-10]` Implement the selected Nest Cards setup/login UI in `login_live.ex` and shared components. Keep draft passwords only in one standard final HTML form—never browser storage or incremental LiveView events—show only usernames/roles in review, warn that later creation/reset is unavailable, require irreversible confirmation, and POST once to `BootstrapController`. Login uses one generic invalid-credentials error.
- [ ] `[AI] [AC-01, AC-03, AC-04, AC-06, AC-07, AC-09, AC-10, AC-11]` Turn authentication unit/integration/behavior/E2E tests green using only isolated synthetic users. Include protected direct navigation, duplicate normalized username, failed bootstrap rollback, cookie flags, browser restart, two simultaneous contexts for one user, one-context logout, multi-role own data, and cross-user denial.

### Phase 2 Checkpoint

- [ ] `[AI] [AC-01, AC-06, AC-07, AC-09, AC-10]` In isolated browsers, complete setup once, confirm setup routes stay closed, log in, restart browser A, log in on browser B, log out A, and prove B remains authenticated. Inspect only synthetic session records and confirm raw tokens/plaintext passwords are absent.
- [ ] `[AI] [AC-03, AC-04]` Run all applicable adapters for the capability matrix and attempted client-supplied owner/path. Every undefined or cross-user action must deny before repository access.
- [ ] `[AI] [AC-09, AC-10]` At 1440×900, 768×1024, and 375×812, compare setup/login with selected hi-fi assets; verify labels, associated errors, keyboard order, visible focus, role checked state beyond color, password clearing, non-password preservation, reduced motion, wrapping, and irreversible-close copy.
- [ ] `[AI] [AC-11]` Stop contexts/server and clean the exact marked root/profile. Prove synthetic family members never appeared in production and no live account/session path changed.
- [ ] `[AI] [AC-01–AC-11]` Re-read Phase 2 from the first item and record any reusable learning before starting import work.

## Phase 3 — Repository, Browser Import, and Legacy Copy

- [ ] `[AI] [AC-02, AC-05, AC-08]` Implement immutable browser-envelope/legacy-copy recovery sources and `manifest.ex` statuses/idempotency exactly as [data contracts](tech-docs/data-contracts.md#migration-records) defines. Unit-test pending, retryable, rejected, accepted, accepted retry, attempt increment, checksum mismatch, and immutable-file collision.
- [ ] `[AI] [AC-02, AC-03, AC-08]` Implement `import.ex` with only `bnest.chat.v1`, `bnest.sifat-allah.v1`, and `phx:theme`. Enforce storage area, byte limit, supported source version/value, current authenticated owner, and server-selected destination before any write.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Add pure normalizers for chat v1/v2, Sifat Allah v1/v2 plus optional activity state, and explicit/absent theme. For every fixture, retain exact source bytes, validate the normalized target, link `sourceImportId`, and prove malformed data cannot replace an accepted record.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Implement the expand→migrate→verify state machine from [migration design](tech-docs/migration-design.md#transition-stages). After candidate write, read through the same typed repository operation used by LiveView; mark accepted only after that passes; return client cleanup only for that accepted source.
- [ ] `[AI] [AC-02, AC-05]` Perform the private root-level source inventory without committing values. For each source, record reader/writer/owner/form/destination safely, require the immutable owner/application legacy copy to match the source checksum, normalize a separate candidate into the mapped `data/prod` record, validate/read back that record, and leave the root-level source unchanged. Unproven ownership must remain opaque with `owner-unresolved`.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Implement `data_migration_live.ex` and source cards: show only recognized sources from the current browser, require confirmation, display ready/copying/verifying/accepted/retryable/rejected using text/icon/color, and retry without asking the user to re-enter payloads.
- [ ] `[AI] [AC-02, AC-08]` Update `assets/js/app.js` so it never enumerates storage or accepts a server path. Remove only the exact accepted Bnest key after server acknowledgement; preserve every other key and stop future persistent chat/quiz/theme writes for that accepted record.
- [ ] `[AI] [AC-02, AC-03, AC-05, AC-07, AC-08, AC-11]` Turn centralized-data unit/integration/behavior/E2E tests green. Cover absent, accepted, duplicate, oversized, unknown, malformed, interrupted, read-back-failed, stale-revision, cleanup-pending, two-user, two-browser, theme-system, legacy opaque, and failed Codex-resume outcomes.
- [ ] `[HUMAN] [AC-02, AC-05, AC-08]` In each authorized live browser, confirm only the displayed allow-listed sources after Bnest can create the immutable envelope. This grants only browser confirmation and live import; do not disclose credentials, cookie, private URL, path, checksum, or payload to the agent.

### Phase 3 Checkpoint

- [ ] `[AI] [AC-02, AC-05, AC-08]` Re-run the complete failure matrix. Prove every source is unchanged until acceptance, every failed candidate leaves prior accepted data readable, duplicate acceptance is idempotent, and only accepted browser keys are removed.
- [ ] `[AI] [AC-02, AC-05]` Compare each source checksum with its recovery-copy checksum, then validate the separately normalized destination's schema, owner, source identity, and normal read-back. Rehearse restore with synthetic bytes and prove every root-level legacy source remains unchanged.
- [ ] `[AI] [AC-02, AC-03, AC-08]` Reload chat, Sifat Allah, and theme through normal authenticated flows after client cleanup; confirm final durable state exists only below the user's runtime path and no browser Bnest persistence is recreated.
- [ ] `[AI] [AC-11]` Stop all test processes, validate exact cleanup, and prove production was never used as a behavior-test root.
- [ ] `[AI] [AC-01–AC-11]` Re-read Phase 3 from its first item and record migration/recovery learning before cutover verification.

## Phase 4 — Final Proof, Documentation, and Handoff

- [ ] `[AI] [AC-01–AC-11]` Run `npm exec -- nx run -p bnest-app -t test:quick`, affected `bnest-app:test:integration`, and only the affected `bnest-app-e2e:test:e2e` scenarios. Record target, scenario/test name, result, and safe failure summary; rerun a target only after addressing its failure.
- [ ] `[AI] [AC-01–AC-11]` With Playwright MCP and one marked synthetic run, manually verify setup closure, invalid login, persistent browser restart, same-user two-browser independence, cross-user denial, each browser source import, read-back, client cleanup, retry, chat continuation/fresh-thread fallback, learning continuation, and theme behavior.
- [ ] `[AI] [AC-09, AC-10]` Repeat the affected setup/login/import states at desktop, tablet, and mobile. Run the changed-file accessibility check and manually inspect semantics, keyboard, focus, errors, checked/status non-color cues, reduced motion, zoom/reflow, and password non-retention.
- [ ] `[AI] [AC-05]` Rehearse restore once more from the immutable synthetic envelope/legacy copy while writes are stopped. Prove checksum, schema, atomic replacement, and normal product read-back; then clean only the marked run.
- [ ] `[AI] [AC-01–AC-10]` Update the selected C4/Gherkin, app/E2E READMEs, and operations guidance to the final as-built implementation. Reconcile every path in [File Impact](tech-docs/file-impact.md); explain any evidence-backed deviation in this plan before changing the tree.
- [ ] `[AI] [AC-01–AC-11]` Capture only safe evidence and route each learning to a specification, permanent documentation, governance, an existing idea, or a distinct new idea after searching `plans/ideas/`. Do not duplicate ideas or retain secrets/runtime values.

### Phase 4 Checkpoint

- [ ] `[AI] [AC-01–AC-11]` Re-run the plan quality gate from step 1, reconcile every delivery checkbox with repository evidence, and rerun required Nx gates. Confirm all selected behavior, migration, UI, cleanup, rollback, docs, and specifications are complete with no unresolved material gap.
- [ ] `[HUMAN] [AC-02, AC-05, AC-08]` Decide whether to request a separate archival plan. The default is retain every envelope, recovery copy, manifest, old reader, and root-level legacy source; this item authorizes no deletion.
- [ ] `[AI] [AC-01–AC-11]` When every prior item passes, follow plan execution to move the folder to `plans/done/YYYY-MM-DD__bnest-centralized-data/`, update both directory maps, and record the completion date. This does not independently authorize commit or push.

## Live Rollback

- [ ] `[HUMAN] [AC-05]` Authorize and perform the operational stop of new live centralized writes. State only that writes are stopped; do not expose live access details.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Read the safe manifest status, preserve every source and accepted record, verify the selected recovery source in place, and prepare the exact restore operation without a live mutation beyond granted authority.
- [ ] `[HUMAN] [AC-05]` Choose the verified recovery source or retained previous representation and authorize that exact live restore target.
- [ ] `[AI] [AC-05]` Execute only the authorized restore, re-read it through the normal product flow, stop if checksum/schema/read-back fails, and retain the failed candidate plus previous accepted data.
- [ ] `[AI] [AC-01–AC-11]` Record safe failure evidence and route reusable learning before resuming delivery or marking the plan complete.
