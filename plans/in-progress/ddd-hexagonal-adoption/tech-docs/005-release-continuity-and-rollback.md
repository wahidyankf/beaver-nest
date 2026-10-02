# 005: Release, Continuity and Rollback

This plan changes an active service, so [live-service continuity](../../../../repo-governance/development/live-service-continuity.md)
and the [Caddy deployment workflow](../../../../repo-governance/workflows/maintenance/development-caddy-deployment.md) apply in full.
[Releasing Bnest](../../../../docs/how-to-guides/releasing-bnest.md) is the procedure.

## What Is Released

The `origin/main` revision after U14 lands: the closure revision. U4–U13 each leave `main` deployable (a refactor with
all gates green), but only the closure revision is released. Each release proves the whole architecture at once, and
the owner's goal names one production deployment. The production release is authorized for that revision under
[release authorization](../../../../repo-governance/conventions/release-authorization.md). That authorization covers
the documented sequence, including an `--mode experience` re-promotion when the active production slot runs with the
feature flags on.

## Why Two Revisions Can Share the Host Safely

| Concern              | Evidence                                                                                                                                 | Consequence                                                                                                                                                                                                                 |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Schema               | No file under `priv/sqlite_repo/migrations/` changes (AC-DH-09)                                                                          | The manifest declares the same migration set as the base revision (`bnest-persistent-schedules-v1`, already applied in production) with the same `migrationSetChecksum`; its idempotent `apply_and_verify!` changes nothing |
| Stored records       | No record kind, schema version or canonical JSON form changes                                                                            | Old and new slots read and write the same records                                                                                                                                                                           |
| SQLite locking       | Adapters issue the same SQL, under the same `Storage` lock, against the same database file                                               | Mixed-version writes stay mutually compatible                                                                                                                                                                               |
| PubSub               | Slots are unclustered (`BnestApp.FamilyChat` documents slot-local broadcast, and the "independent slot-local PubSub" scenario covers it) | Renamed structs never cross slots                                                                                                                                                                                           |
| Process names        | `BnestApp.DataRepository` becomes `BnestApp.Storage.Records`, and `Codex.ModelCatalog` becomes `CodexChat.ModelCatalog`                  | Names are node-local; readiness (`Operations.readiness/0`) checks the new names in the new slot                                                                                                                             |
| Eval entry points    | `BnestApp.Release.Migrations.*` names are frozen                                                                                         | `tools/deployment.mjs` keeps working unchanged                                                                                                                                                                              |
| Session and LiveView | Cookie key base, session format, routes and LiveView events unchanged                                                                    | Compatible LiveViews reconnect during the 5-minute drain without a manual refresh                                                                                                                                           |

## Sequence

All commands run from the **primary checkout** (the repository root) on local `main`, prefixed with `rtk`.

1. **Reconcile.** `git fetch origin`, then `git merge --ff-only origin/main`. Prove that
   `git rev-list --left-right --count HEAD...origin/main` reads `0 0` and that `git status --porcelain` is empty.
2. **Configure.** Source the machine-local `deploy-env.sh` described in the release guide. If it is absent, derive it
   from the active launchd unit; secret paths only, never contents.
3. **Read the active mode.** Use `PlistBuddy` on the active slot's unit to report whether `BNEST_FAMILY_CHAT_ENABLED` and
   `BNEST_FAMILY_CHAT_REPLY_ENABLED` are `true`. This decides whether step 7 runs.
4. **Free the inactive slot.** Identify the routed slot from `proxy:status` and the routed `/health/ready`. If the
   other slot listens and is not routed, retire it once with `deploy:retire -- --slot <colour>` (the tool itself
   refuses the active slot). If routing is ambiguous or the retire fails, stop and report to the owner.
   **Preflight.** `proxy:status`; local and routed `/health/ready`; at least 12 samples of the exact production origin;
   a representative journey; `./hippo status` normal; the inactive slot free.
   - Budget: zero failures, p95 ≤ 500 ms, every sample ≤ 2 s.
   - A breach stops the release, and the active route is restored before anything else.
5. **Continuous sampling.** A background sampler hits the exact origin every 2 s and writes to
   `local-tmp/ddd-hexa/release-samples.ndjson` from preflight until drain completes.
6. **Release.** `npm exec -- nx run -p bnest-app -t release:run -- --revision <closure-sha>` (self-guarded; no outer
   hippo). `queued`/`deferred` outcomes retry once the cause clears.
7. **Experience re-promotion** (only if step 3 found the flags on):
   `npm exec -- nx run -p bnest-app -t release:run -- --mode experience --revision <closure-sha>`.
8. **Routed proof.**
   - Local Caddy (`127.0.0.1:4100`) and Tailnet HTTPS `/health/ready` both report `X-Bnest-Revision` = closure SHA.
   - `tools/verify-liveview.mjs` connects a synthetic LiveView at the exact origin.
   - The same tool disconnects and reconnects its ten LiveView clients, and its JSON must report
     `reconnected: true`. `UserSocket` reconnect across a promotion is proven before release by the fe-e2e
     scenario "A connected client reconnects to the promoted slot without a page refresh" (Phase 14 `FE_E2E`), because
     a production witness would need a real household session.
   - The sampler summary meets the budget.
9. **Drain and cleanup.** After the 5-minute drain, exactly one slot listens on `4000`/`4001`; `git worktree list` shows
   no release worktree; the sampler is stopped.

## Rollback

| Trigger                                                                         | Action                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Candidate health, revision header, LiveView verification, or routed proof fails | `npm exec -- nx run -p bnest-app -t deploy:rollback`, then diagnose; never retry a failed candidate blind                                                                                                                                                                                                                               |
| Any sample fails or the budget is exceeded during promotion or drain            | `deploy:rollback` immediately, then re-verify the journey and budget                                                                                                                                                                                                                                                                    |
| A defect is found after the drain completes                                     | Ask the owner to confirm re-releasing the previous revision (`release:run -- --revision <previous-sha>`), because [release authorization](../../../../repo-governance/conventions/release-authorization.md) covers one revision. The re-release is safe because no schema or record format changed. Record the defect in `learnings.md` |

Each trigger stays unticked with an evidence-backed `Not triggered` disposition unless it fires.
