# Bnest Backend Architecture

This is the canonical as-built C4 model for Bnest's backend surface: authentication/authorization at the server
boundary, SQLite, Scheduler, Backup, and internal services. Maintain it under the repository
[architecture specification standard](../../../../repo-governance/development/architecture-specifications.md). The
frontend surface is documented separately at [`app-fe/architecture.md`](../app-fe/architecture.md); both surfaces are
delivered by the one running `bnest-app` process and are aggregated by [`specs/apps/bnest/README.md`](../README.md).

## System Context

```mermaid
flowchart TB
    accTitle: System Context
    accDescr: Flowchart with 8 nodes and 7 connections. Nodes: Person Family member Uses the private family application, Person Administrator Manages schedules and backup settings, External system Tailscale Serve Private HTTPS route to stable local proxy, Container Caddy Loopback reverse proxy Blue/green upstream drain, Software system Bnest backend Authenticated data Scheduled backups, External system Local Codex installation Model discovery Read-only Codex threads, External system Dropbox sync client Synchronizes verified backup pairs, External system Browser-vendor Web Push service Delivers VAPID-signed encrypted payloads. Connections: Person Family member Uses the private family application to External system Tailscale Serve Private HTTPS route to stable local proxy (Browser requests via app-fe), Person Administrator Manages schedules and backup settings to External system Tailscale Serve Private HTTPS route to stable local proxy (Admin requests via app-fe), External system Tailscale Serve Private HTTPS route to stable local proxy to Container Caddy Loopback reverse proxy Blue/green upstream drain (Loopback HTTP), Container Caddy Loopback reverse proxy Blue/green upstream drain to Software system Bnest backend Authenticated data Scheduled backups (Loopback HTTP WebSocket), Software system Bnest backend Authenticated data Scheduled backups to External system Local Codex installation Model discovery Read-only Codex threads (Local processes), Software system Bnest backend Authenticated data Scheduled backups to External system Dropbox sync client Synchronizes verified backup pairs (Verified snapshot pairs), Software system Bnest backend Authenticated data Scheduled backups to External system Browser-vendor Web Push service Delivers VAPID-signed encrypted payloads (Signed encrypted push payloads).
    visitor(["Person<br/><b>Family member</b><br/>Uses the private<br/>family application"])
    admin(["Person<br/><b>Administrator</b><br/>Manages schedules<br/>and backup settings"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Private HTTPS route<br/>to stable local proxy"}}
    caddy["Container<br/><b>Caddy</b><br/>Loopback reverse proxy<br/>Blue/green upstream drain"]
    backend[["Software system<br/><b>Bnest backend</b><br/>Authenticated data<br/>Scheduled backups"]]
    codex{{"External system<br/><b>Local Codex installation</b><br/>Model discovery<br/>Read-only Codex threads"}}
    dropbox{{"External system<br/><b>Dropbox sync client</b><br/>Synchronizes verified<br/>backup pairs"}}
    webpush{{"External system<br/><b>Browser-vendor<br/>Web Push service</b><br/>Delivers VAPID-signed<br/>encrypted payloads"}}

    visitor -.->|Browser requests<br/>via app-fe| tailscale
    admin -.->|Admin requests<br/>via app-fe| tailscale
    tailscale -->|Loopback HTTP| caddy
    caddy -->|Loopback HTTP<br/>WebSocket| backend
    backend -->|Local processes| codex
    backend -->|Verified snapshot pairs| dropbox
    backend -->|Signed encrypted<br/>push payloads| webpush

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef system fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor,admin person
    class backend system
    class tailscale,codex,dropbox,webpush external
    class caddy system
    classDef default fill:#FFFFFF,stroke:#000000,color:#000000
```

The backend surface serves every authenticated request and scheduled job for the one 24/7 `bnest-app` process. Family
members and administrators never call it directly; every request arrives through the rendered routes owned by
[`app-fe`](../app-fe/architecture.md), which forwards it across the same HTTP/WebSocket boundary this document owns.
Elixir/OTP and Phoenix were selected for supervision, process isolation, and durable scheduled work. Bnest keeps
user-owned state and durable schedule claims in a server-managed local SQLite database; verified legacy flat files are
retired after cutover instead of remaining as an unbounded rollback copy. It publishes independently verified
snapshot pairs to an ignored folder observed by Dropbox, but the sync client is neither authoritative storage nor
complete disaster recovery. The compatibility revision adds an authenticated GraphQL surface (queries, mutations, and
an Absinthe subscription) serving the family chat feature, plus outbound Web Push delivery to each participant's
subscribed browser endpoints; both are implemented and tested behind the `BNEST_FAMILY_CHAT_ENABLED` flag, which
still defaults to off in this revision (see [Architectural Constraints](#architectural-constraints)).

## Container View

```mermaid
flowchart TB
    accTitle: Container View
    accDescr: Flowchart with 9 nodes and 8 connections. Nodes: External container app-fe browser/PWA See app-fe/architecture.md, External system Local Codex installation, External system Dropbox sync client, External system Web Push service, Container Phoenix backend domain Elixir / Phoenix / Bandit, Container / data store Local SQLite database Records and schedules Claims and safe results, Container / data store Backup folder Owned snapshots and safe receipts, Container / data store Legacy flat files Migration source Removed after proof, Container Codex bridge processes Node.js / Codex SDK and CLI. Connections: Container Phoenix backend domain Elixir / Phoenix / Bandit to Container / data store Local SQLite database Records and schedules Claims and safe results (Typed atomic operations), Container Phoenix backend domain Elixir / Phoenix / Bandit to Container / data store Backup folder Owned snapshots and safe receipts (Verified owned pairs), Container / data store Legacy flat files Migration source Removed after proof to Container Phoenix backend domain Elixir / Phoenix / Bandit (Verified migration input), Container Phoenix backend domain Elixir / Phoenix / Bandit to Container Codex bridge processes Node.js / Codex SDK and CLI (Ports and JSON lines), External container app-fe browser/PWA See app-fe/architecture.md to Container Phoenix backend domain Elixir / Phoenix / Bandit (HTTP and WebSocket events, session cookie), Container Codex bridge processes Node.js / Codex SDK and CLI to External system Local Codex installation (Discovers models runs or resumes threads), Container / data store Backup folder Owned snapshots and safe receipts to External system Dropbox sync client (Filesystem sync), Container Phoenix backend domain Elixir / Phoenix / Bandit to External system Web Push service (Signed encrypted push payloads).
    frontend[["External container<br/><b>app-fe browser/PWA</b><br/>See app-fe/architecture.md"]]
    codex{{"External system<br/><b>Local Codex installation</b>"}}
    dropbox{{"External system<br/><b>Dropbox sync client</b>"}}
    webpush{{"External system<br/><b>Web Push service</b>"}}

    subgraph backend["Software system: Bnest backend"]
        direction TB
        phoenix["Container<br/><b>Phoenix backend domain</b><br/>Elixir / Phoenix / Bandit"]
        runtime[("Container / data store<br/><b>Local SQLite database</b><br/>Records and schedules<br/>Claims and safe results")]
        backup[("Container / data store<br/><b>Backup folder</b><br/>Owned snapshots<br/>and safe receipts")]
        legacy_runtime[("Container / data store<br/><b>Legacy flat files</b><br/>Migration source<br/>Removed after proof")]
        bridge["Container<br/><b>Codex bridge processes</b><br/>Node.js / Codex SDK and CLI"]

        phoenix -->|Typed atomic operations| runtime
        phoenix -->|Verified owned pairs| backup
        legacy_runtime -->|Verified migration input| phoenix
        phoenix -->|Ports and JSON lines| bridge
    end

    frontend -->|HTTP and WebSocket<br/>events, session cookie| phoenix
    bridge -->|Discovers models<br/>runs or resumes threads| codex
    backup -->|Filesystem sync| dropbox
    phoenix -->|Signed encrypted<br/>push payloads| webpush

    classDef container fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    classDef external fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    class phoenix,bridge container
    class runtime,legacy_runtime,backup data
    class frontend,codex,dropbox,webpush external
    classDef default fill:#FFFFFF,stroke:#000000,color:#000000
```

The Phoenix backend domain, SQLite storage, temporary flat-file migration source, backup folder, and Node bridges run
on the home host. The stable storage pointer remains at `~/.config/bnest/storage.json`, while the default production
database lives at `~/bnest/data/prod/bnest.sqlite3`. A separate private pointer optionally overrides the exact
ignored `data/backup/` default. Verified flat sources under `data/prod/` are removed after routed storage proof.
Filesystem test fixtures remain in a marked Dropbox run below `data/test/runs/`, while the paired SQLite database uses
the same run identifier below `~/bnest/data/test/runs/`; both roots are cleaned after the run.

## Release and Resumable State

The managed release controller serializes each clean `origin/main` revision through one fail-closed transaction.
Production slots own `4000` and `4001`, Caddy owns `4100`, isolated E2E leases `4010`–`4039`, and development leases
`4020`–`4029`. Every managed slot enables secure cookies and account identity cutover, so a logged-out root request
follows the login boundary instead of receiving a synthetic legacy user. The controller creates no artifact until
every fixed gate passes, refuses an undeclared migration adapter, and leaves the proven route active when only final
cleanup needs retrying. A private release-overlap monitor follows the logged-out root-to-login journey while
sampling explicit local health and the exact routed user surface from preflight through drain; schema-v5 evidence
rejects any routed failure, p95 latency above 500 ms, or individual sample above 2 seconds without persisting the
private origin.

```mermaid
flowchart TD
    accTitle: Release and Resumable State
    accDescr: Flowchart with 10 nodes and 9 connections. Nodes: Clean origin main, Fixed uncached gates, Immutable artifact, Migration proof, Inactive slot proof, Caddy promotion, Routed revision proof, Ten-client reconnect, Bounded five-minute drain, Retain active and previous. Connections: Clean origin main to Fixed uncached gates, Fixed uncached gates to Immutable artifact, Immutable artifact to Migration proof, Migration proof to Inactive slot proof, Inactive slot proof to Caddy promotion, Caddy promotion to Routed revision proof, Routed revision proof to Ten-client reconnect, Ten-client reconnect to Bounded five-minute drain, Bounded five-minute drain to Retain active and previous.
    source[Clean origin main] --> gates[Fixed uncached gates]
    gates --> artifact[Immutable artifact]
    artifact --> migration[Migration proof]
    migration --> candidate[Inactive slot proof]
    candidate --> promote[Caddy promotion]
    promote --> routed[Routed revision proof]
    routed --> reconnect[Ten-client reconnect]
    reconnect --> drain[Bounded five-minute drain]
    drain --> cleanup[Retain active and previous]

    classDef input fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    classDef stage fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef proof fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    class source input
    class gates,artifact,migration,candidate,promote,drain stage
    class routed,reconnect,cleanup proof
    classDef default fill:#FFFFFF,stroke:#000000,color:#000000
```

Backend session and durable-record continuity are the foundation `app-fe`'s reconnect experience relies on: a
compatible transport reconnect restores the same authoritated session and server-owned records without this backend
losing or duplicating state. Blue/green release slots remain independent; no cross-slot PubSub is assumed by this
backend today.

## Component View

```mermaid
flowchart TB
    accTitle: Component View
    accDescr: Flowchart with 14 nodes and 27 connections. Nodes: External container app-fe browser/PWA, External container Codex bridge processes, External system Web Push service, Component Inbound adapters BnestAppWeb, BnestAppCli Release entry points, Context Identity Bootstrap, login, sessions Roles and authorization, Context Preferences Per-user theme, Context Storage Records, lock, lifecycle Import and recovery, Context Operations Admin panels Liveness and readiness, Context Scheduler Claims and retries Configured task ports, Context Backup VACUUM and quick check Receipts, retention, reconciliation, restore drill, Context CodexChat Transcripts, model access Agent session port, Context SifatAllah Quiz and progress, Context FamilyChat Rooms and messages Replies and publishing, and 1 more. Connections: app-fe to Inbound adapters (Opaque cookie, events, GraphQL over UserSocket), Inbound adapters to each of the ten context facades, Identity to Storage (Accounts and sessions), Operations to Scheduler and Storage, FamilyChat to Scheduler (Catch-up convergence), PushNotifications to FamilyChat (Committed messages), Scheduler to Backup and PushNotifications (Dispatches claims through task ports), Preferences, CodexChat, SifatAllah, Scheduler, Backup, PushNotifications and FamilyChat to Storage (Records through adapters), CodexChat to Codex bridge processes (Ports and JSON lines), and PushNotifications to Web Push service (Signed encrypted push payloads).
    frontend(["External container<br/><b>app-fe browser/PWA</b>"])
    bridge{{"External container<br/><b>Codex bridge processes</b>"}}
    webpush{{"External system<br/><b>Web Push service</b>"}}

    subgraph phoenix["Container: Phoenix<br/>backend domain"]
        direction TB

        inbound["Component<br/><b>Inbound adapters</b><br/>BnestAppWeb, BnestAppCli<br/>Release entry points"]
        identity["Context<br/><b>Identity</b><br/>Bootstrap, login, sessions<br/>Roles and authorization"]
        preferences["Context<br/><b>Preferences</b><br/>Per-user theme"]
        storage["Context<br/><b>Storage</b><br/>Records, lock, lifecycle<br/>Import and recovery"]
        operations["Context<br/><b>Operations</b><br/>Admin panels<br/>Liveness and readiness"]
        scheduler["Context<br/><b>Scheduler</b><br/>Claims and retries<br/>Configured task ports"]
        backup["Context<br/><b>Backup</b><br/>VACUUM and quick check<br/>Receipts, retention,<br/>reconciliation, restore drill"]
        codexchat["Context<br/><b>CodexChat</b><br/>Transcripts, model access<br/>Agent session port"]
        sifatallah["Context<br/><b>SifatAllah</b><br/>Quiz and progress"]
        familychat["Context<br/><b>FamilyChat</b><br/>Rooms and messages<br/>Replies and publishing"]
        push["Context<br/><b>PushNotifications</b><br/>VAPID delivery, retry<br/>Retention task"]

        inbound --> identity
        inbound --> preferences
        inbound --> storage
        inbound --> operations
        inbound --> scheduler
        inbound --> backup
        inbound --> codexchat
        inbound --> sifatallah
        inbound --> familychat
        inbound --> push
        identity -->|Accounts and sessions| storage
        operations -->|Schedule state| scheduler
        operations -->|Storage lifecycle| storage
        familychat -->|Catch-up convergence| scheduler
        push -->|Committed messages| familychat
        scheduler -->|Dispatches claims<br/>through task ports| backup
        scheduler -->|Dispatches retention<br/>claims via task ports| push
        preferences -->|Records through<br/>adapters| storage
        codexchat -->|Records through<br/>adapters| storage
        sifatallah -->|Records through<br/>adapters| storage
        scheduler -->|Schedule ledger<br/>through adapters| storage
        backup -->|Snapshot source<br/>through adapters| storage
        push -->|Subscriptions<br/>through adapters| storage
        familychat -->|Rooms and messages<br/>through adapters| storage
    end

    frontend -->|Opaque cookie, events,<br/>GraphQL over UserSocket| inbound
    codexchat -->|Ports and JSON lines| bridge
    push -->|Signed encrypted<br/>push payloads| webpush

    classDef external fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef component fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef process fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class frontend external
    class inbound,identity,preferences,storage,operations,scheduler,backup,codexchat,sifatallah,familychat,push component
    class bridge,webpush process
    classDef default fill:#FFFFFF,stroke:#000000,color:#000000
```

`app-fe` owns the LiveView route/presentation layer (`ChatLive`, `SifatAllahLive`) that renders this domain's state;
this document owns only the domain components those routes call into. Family chat is a materially different pattern:
`app-fe` renders it through a plain Phoenix controller route (`FamilyChatController`, not a LiveView), and the
browser drives every read/write itself through one authenticated GraphQL schema exposed at `/api/graphql`:
`family_chat_rooms`, `family_chat_room`, and `family_chat_messages` queries; `send_family_chat_message` mutation,
which accepts an optional `reply_to_message_id` naming an already-committed message in the same room; and
`family_chat_message_committed` subscription. Every message the schema returns carries an optional `reply_to` quote
(`id`, `sender_kind`, `sender_display_name`, and a server-bounded `body_preview`), which is a distinct object type
rather than a recursive message, so a quote can never carry a quote of its own. All are served by the `familychat`
component, with subscription identity
resolved only from the server-decoded session carried in `UserSocket`'s `connect_info` — never from client-supplied
socket params. Push-subscription lifecycle (`web_push_configuration`, `current_web_push_subscription` queries;
`upsert_web_push_subscription`, `disable_current_web_push_subscription` mutations) is served through that same
schema and routed into the `push` component. Push notifications also owns a second, independent
`Scheduler.TaskRegistry` handler (`family_chat_push_retention`, routed to `PushNotifications.Adapters.RetentionTask`)
alongside the pre-existing backup handler; both share the same daily-scheduler claim/retry/lease machinery in
`scheduler` but dispatch to unrelated allowlisted handler modules. `BnestApp.CodexChat` (the Codex conversation
context) and the family chat feature are unrelated: distinct schemas, distinct transports (LiveView events vs.
GraphQL/Absinthe subscription), and distinct data stores.

Each node is a bounded context published through one facade module, `BnestApp.<Context>`, with the context's pure
`Domain`, outbound `Ports`, and effectful `Adapters` beneath it: `BnestApp.Identity` (bootstrap, login, sessions,
roles, and the authorization policy), `BnestApp.Preferences`, `BnestApp.Storage` (records, the path lock, the storage
lifecycle, import, and recovery), `BnestApp.Operations` (admin panels, liveness, readiness, and the release revision),
`BnestApp.Scheduler`, `BnestApp.Backup`, `BnestApp.CodexChat`, `BnestApp.SifatAllah`, `BnestApp.FamilyChat`, and
`BnestApp.PushNotifications`. A context reaches another only through that context's facade, except that every
context reaches `Storage` through its own adapters, and `Scheduler` reaches `Backup` and `PushNotifications` only
through the task ports it is configured with. `BnestApp.SqliteRepo`, `BnestApp.Application`, and `BnestApp.Release`
are the infrastructure owners the contexts' adapters and the release entry points use.

Backup also owns **reconciliation**: `BnestApp.Backup.reconcile/2` compares the verified runs the Scheduler reports
(`BnestApp.Scheduler.verified_runs/1`, one read-only query on the `ScheduleStore` port) with the owned artifacts present
in the destination, and the pure `Backup.Domain.Reconciliation` classifies each expected run as present, missing or
changed, over the same retained WIB dates `Retention` uses. Reconciliation reads through the `ArtifactStore` port only
and writes nothing. One wording function in `Reconciliation` renders the result for every surface, so the post-run log
line and telemetry event the Backup task emits after retention, the `mix bnest.backup.reconcile` report and the
Schedules page label cannot disagree about the result. Only the advice of a check that could not be made differs by
audience: the task and the log line name the operator's command, while the label asks the reader to reload the page. A second Mix task, `mix bnest.backup.restore_drill --artifact <basename>`, is a
thin inbound adapter over `Backup.restore/1`. It reads the destination as `Backup.read_destination/0` names it, never
creating or marking it, and `Backup.restore_target/2` accepts the artifact only as a bare file name that resolves to a
regular file inside that destination, through the `ArtifactStore` port: a path outside the destination, a path that
climbs out of it, a missing file, a directory and a symbolic link are all refused with one fixed line and a non-zero
exit before anything is restored. It restores through `Backup.restore/1` into the root that call creates and removes
and prints the redacted evidence it returns (counts, order and states, never a path, a message body or a push
credential). Around that call it lists the operating system's temporary directory through `Backup.restore_roots/0`,
and a restore root that is there afterwards and was not there before is reported as not removed with a non-zero exit.
One pure function, `Backup.Domain.RestoreDrillReport`, words the result, so a failure is always one fixed line that
carries no error message. Neither task starts the Scheduler.

## Architectural Constraints

- Every protected route and data operation resolves an unrevoked opaque-cookie session and current user before
  repository access.
- Bootstrap, username indexes, accounts, and browser sessions use the phase-aware repository; SQLite authority never
  reads a retired flat identity source.
- Roles may contain `children`, `parents`, and `admin`; capabilities still default-deny cross-user access.
- Codex model access is role-scoped server-side: admins receive the discovered catalog, parents use Terra at medium
  effort, and children use Luna at medium effort. A missing required model disables that role's chat instead of
  substituting another model.
- Durable chat, Sifat Allah progress, and explicit theme state live in the authenticated user's SQLite records after
  accepted import.
- Daily definitions, unique claims, retry state, leases, occurrence expiry, and safe results live in SQLite. One
  generic coordinator dispatches code-allowlisted handlers from both schedule contexts and never trusts executable
  names from stored data.
- The production SQLite backup schedule never expires. It verifies a `VACUUM INTO` snapshot through an independent
  read-only connection, checks the attempt fence before atomic publication, and retains only owned receipt-backed
  pairs for the latest seven WIB dates.
- Backup reconciliation is read-only: it writes no file, removes no file and changes no ledger row, and a failure of
  the post-run reconciliation never changes a backup run's recorded outcome. `mix bnest.backup.reconcile` never opens
  the production SQLite file: it reads the ledger from scratch copies of the database and its `-wal` sidecar, starts
  only the repository on a copy, and starts no Scheduler, so a read cannot claim a slot.
- `mix bnest.backup.restore_drill` never opens the live database: it takes no snapshot of it, starts no repository on it
  and starts no Scheduler. It restores only a regular file inside the configured backup destination, leaves that
  destination unchanged and leaves nothing behind in the operating system's temporary directory.
- Only the exact Git-ignored `data/backup/` path may be used inside the repository. External overrides reject
  symbolic links, live-source/config overlap, and unsafe repository paths; no route downloads or exposes backup
  paths or payloads.
- Browser keys are immutable compatibility sources until envelope, normalization, and normal read-back pass; only the
  accepted key is then cleared by `app-fe`.
- Mutable records use revision checks, one path lock coordinated across connected local BEAM release nodes, atomic
  replacement, and read-back. Sessions have no time expiry and remain independent per browser.
- Test adapters use only synthetic `test-user-` identities and paired marked flat-file and SQLite run roots;
  production structural audit is read-only.
- Each bounded context publishes one facade, `BnestApp.<Context>`. Inbound adapters (`BnestAppWeb`, `BnestAppCli`,
  release entry points) call only facades and exported domain types, and a context calls another only through its
  facade. The `boundary` compiler fails `typecheck` on any other edge, and every module under `lib/bnest_app` belongs
  to a strict context or to a named infrastructure owner.
- Only `*.Adapters.*` modules, `BnestApp.SqliteRepo`, `BnestApp.Application` and `BnestApp.Release.*` perform effects:
  SQL, filesystem, network and operating-system calls. Domain modules are pure. The hexagonal layering integration
  test enforces both rules, and test workloads and doubles live under `test/`, never in `lib/`.
- Routine releases are clean-revision transactions owning release and resource locks, with fixed uncached gates,
  capacity and port admission, immutable artifact and migration manifests, revision proofs, rollback, bounded drain,
  and two-artifact retention. Repository-owned development consumes fixed CPU-and-memory allocations from the shared
  reservation ledger; independent work may overlap, targeted warning/critical shedding remains owner-controlled, and
  HIPPO never signals production, Caddy, or unrelated processes.
- The GraphQL schema exposes no system-message mutation; system messages (room joins, retention notices) are
  server-originated only. A dedicated source-scan test (`SchemaSourceScan`) and a Scheduler-to-store
  dependency-direction test keep the GraphQL boundary and the Scheduler/handler/service/store call direction
  regression-proof.
- Web Push delivery signs every payload with a server-held VAPID keypair sourced from
  `BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE`/`BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE` and a validated `mailto:`/HTTPS
  `BNEST_WEB_PUSH_SUBJECT`; delivery retries and the retention job's purge window are bounded, and a failed
  subscription is soft-deleted rather than retried unboundedly.
- A message's reply quote is a **read-time derivation** inside the `familychat` component, never a stored copy and
  never a resolver-layer query: the row holds only `reply_to_message_id`, and the quoted sender and body preview are
  resolved from the referenced row when the page is read. One batched lookup serves a whole page. This depends on
  `family_chat_messages` remaining append-only by trigger, which is what makes a reference safe where other products
  denormalize.
- The family chat feature (GraphQL schema, resolvers, push delivery, and the second Scheduler handler) is fully
  implemented and tested but gated end-to-end behind `BNEST_FAMILY_CHAT_ENABLED`, which still defaults to `false`
  (off) in this compatibility revision; only a later experience-release phase flips it on in production.

## Behaviour Traceability

Executable backend behaviour is specified in [`behaviours/`](behaviours/). `bnest-app`'s unit and local-only
integration adapters, aggregated with [`app-fe`](../app-fe/architecture.md)'s root, must implement that exact
recursive corpus; `bnest-app-be-e2e` implements this root's E2E adapter alone.
