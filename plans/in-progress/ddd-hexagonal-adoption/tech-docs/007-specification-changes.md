# 007: Specification Changes

This document follows the
[plan specification-change convention](../../../../repo-governance/conventions/plan-specification-changes.md). The
plan changes architecture, not observable behaviour, so no Gherkin file changes and one C4 file changes.

## Which Outcomes Become Durable Contracts

| PRD outcome | Disposition | Target or reason | Verification |
| --- | --- | --- | --- |
| AC-DH-02 every module belongs to a boundary | C4 contract | `specs/apps/bnest/app-be/architecture.md`, Component View | `delivery.md` Phase 14 C4 task |
| AC-DH-03 crossing a layer fails the gate | C4 contract | same file, Architectural Constraints | Phase 14 C4 task |
| AC-DH-04 effects only in adapters | C4 contract | same file, Architectural Constraints | Phase 14 C4 task |
| AC-DH-05 contexts talk through facades | C4 contract | same file, Component View relationships and Architectural Constraints | Phase 14 C4 task |
| AC-DH-01 standard exists and is linked | Plan-only | A governance property; the standard itself is the durable owner | Phase 2 link proof |
| AC-DH-06 unit layer isolated | Plan-only | A test-architecture property; `test/behaviour/verify.exs` enforces it permanently | Phase 14 RED/GREEN items |
| AC-DH-07 in-memory adapters proven | Plan-only | The contract suites are the durable owner | Each context phase's contract items |
| AC-DH-08 behaviour unchanged | Plan-only | An invariant of this change, not a lasting behaviour | Phase 14 `FEATURE_DIFF`, gates and e2e items |
| AC-DH-09 persisted state untouched | Plan-only | An invariant of this change. `release.mjs` derives the manifest's migration set and `migrationSetChecksum` only from its own constants and the migration file, so an empty `FEATURE_DIFF` over `apps/bnest-app/tools` and `priv/sqlite_repo/migrations` implies an equal checksum | Phase 14 `FEATURE_DIFF` and record-schema items |
| AC-DH-10 production cutover | Plan-only | A one-time release outcome | Phase 15 routed proof |

## Gherkin Files

None. Every `specs/apps/bnest/**/*.feature` file is unchanged, and `FEATURE_DIFF` proves it in each unit.

## `specs/apps/bnest/app-be/architecture.md` [E]

The C4 change is written as-built during U14, from the code that landed. The planned delta:

- **Component View diagram.** The eleven feature-shaped components become one node per bounded context plus one
  inbound-adapter node. Identity absorbs Authorization; Storage absorbs the data repository and import/recovery;
  Operations replaces the admin settings domain; Scheduler absorbs the task supervisor; the chat and learning domain
  splits into CodexChat and SifatAllah; Preferences is new.

```diff
-        identity["Component<br/><b>Identity</b><br/>Bootstrap and login<br/>Sessions and roles"]
-        auth["Component<br/><b>Authorization</b><br/>Capability plus ownership checks"]
-        repository["Component<br/><b>Data repository</b><br/>Schemas, coordinator<br/>Ecto repo and phase"]
-        imports["Component<br/><b>Import and recovery</b><br/>Envelopes and manifests<br/>Retry and restore"]
-        settings["Component<br/><b>Admin settings domain</b><br/>Typed panel registry"]
-        scheduler["Component<br/><b>Daily scheduler</b><br/>Claims and retries<br/>Lease coordination"]
-        tasks["Component<br/><b>Task supervisor</b><br/>Allowlisted handlers"]
-        backups["Component<br/><b>Backup proof</b><br/>VACUUM and quick check<br/>Receipts and retention"]
-        appdomain["Component<br/><b>Chat and learning domain</b><br/>BnestApp.Chat, SifatAllah,<br/>model catalog, session port"]
-        familychat["Component<br/><b>Family chat GraphQL</b><br/>Schema, resolvers<br/>Rooms, messages,<br/>subscription"]
-        push["Component<br/><b>Push notifications</b><br/>VAPID delivery, retry<br/>Retention job"]
+        inbound["Component<br/><b>Inbound adapters</b><br/>BnestAppWeb, BnestAppCli<br/>Release entry points"]
+        identity["Context<br/><b>Identity</b><br/>Bootstrap, login, sessions<br/>Roles and authorization"]
+        preferences["Context<br/><b>Preferences</b><br/>Per-user theme"]
+        storage["Context<br/><b>Storage</b><br/>Records, lock, lifecycle<br/>Import and recovery"]
+        operations["Context<br/><b>Operations</b><br/>Admin panels<br/>Liveness and readiness"]
+        scheduler["Context<br/><b>Scheduler</b><br/>Claims and retries<br/>Configured task ports"]
+        backup["Context<br/><b>Backup</b><br/>VACUUM and quick check<br/>Receipts and retention"]
+        codexchat["Context<br/><b>CodexChat</b><br/>Transcripts, model access<br/>Agent session port"]
+        sifatallah["Context<br/><b>SifatAllah</b><br/>Quiz and progress"]
+        familychat["Context<br/><b>FamilyChat</b><br/>Rooms and messages<br/>Replies and publishing"]
+        push["Context<br/><b>PushNotifications</b><br/>VAPID delivery, retry<br/>Retention task"]
```

- = Preserve: the external `frontend`, `bridge` and `webpush` nodes, their colours, and the `accTitle`/`accDescr`
  convention of the file.
- **Relationships.** Every `frontend -->` edge targets `inbound`; `inbound` reaches each context facade; contexts
  depend on `storage` only through their own adapters (`identity`, `preferences`, `codexchat`, `sifatallah`,
  `scheduler`, `push`, `familychat`); `scheduler` dispatches to `backup` and `push` through the configured task port;
  `push` calls `familychat` through its facade; `identity` reaches `push` through its `SubscriptionRevoker` adapter;
  `codexchat` reaches `bridge` and `push` reaches `webpush` through adapters.
- **Prose under the diagram.** `Scheduler.Registry` becomes `Scheduler.TaskRegistry`, `PushNotifications.RetentionJob`
  becomes `PushNotifications.Adapters.RetentionTask`, and `BnestApp.Chat` becomes `BnestApp.CodexChat`. The GraphQL
  operation list and the subscription-identity rule are preserved word for word.
- **Architectural Constraints.**

```diff
+- Each bounded context publishes one facade, `BnestApp.<Context>`. Inbound adapters (`BnestAppWeb`, `BnestAppCli`,
+  release entry points) call only facades and exported domain types, and a context calls another only through its
+  facade. The `boundary` compiler fails `typecheck` on any other edge.
+- Only `*.Adapters.*` modules, `BnestApp.SqliteRepo`, `BnestApp.Application` and `BnestApp.Release.*` perform effects:
+  SQL, filesystem, network and operating-system calls. Domain modules are pure. The hexagonal layering integration
+  test enforces both rules.
```

- = Preserve: every existing constraint, including the `SchemaSourceScan` and Scheduler dependency-direction entry.
- → Bindings: none; no step or driver binds to this file.
- ✓ Proof: `REPO` (Mermaid label and contrast limits, links) exits 0, and every context node names a facade module
  present in `apps/bnest-app/lib` at the closure revision.
