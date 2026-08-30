# Bnest Architecture

This is the canonical as-built C4 model for Bnest. Maintain it under the repository [architecture specification standard](../../../../repo-governance/development/architecture-specifications.md).

## System Context

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, gray #808080
flowchart TB
    visitor(["Person<br/><b>Family member</b><br/>Uses the private<br/>family application"])
    admin(["Person<br/><b>Administrator</b><br/>Manages schedules<br/>and backup settings"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Private HTTPS route<br/>to stable local proxy"}}
    caddy["Container<br/><b>Caddy</b><br/>Loopback reverse proxy<br/>Blue/green upstream drain"]
    bnest[["Software system<br/><b>Bnest</b><br/>Authenticated family experiences<br/>Centralized local data"]]
    codex{{"External system<br/><b>Local Codex installation</b><br/>Model discovery<br/>Read-only Codex threads"}}
    dropbox{{"External system<br/><b>Dropbox sync client</b><br/>Synchronizes verified<br/>backup pairs"}}

    visitor -->|Remote HTTPS / WebSocket| tailscale
    tailscale -->|Loopback HTTP| caddy
    caddy -->|Loopback HTTP<br/>WebSocket| bnest
    visitor -.->|Direct home-host<br/>connection| bnest
    admin -->|Private admin UI| bnest
    bnest -->|Local processes| codex
    bnest -->|Verified snapshot pairs| dropbox

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef system fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor,admin person
    class bnest system
    class tailscale,codex,dropbox external
    class caddy system
```

Bnest is a 24/7 family service, private to the local host and family devices routed through Tailscale Serve and a stable loopback Caddy proxy. Caddy promotes a healthy blue or green Phoenix release with a bounded WebSocket drain; compatible LiveView clients reconnect without a manual refresh. Elixir/OTP and Phoenix were selected for supervision, process isolation, and concurrent long-lived LiveView sessions. Approved users authenticate before protected access, and only administrators reach schedule or backup configuration. Bnest keeps user-owned state and durable schedule claims in a server-managed local SQLite database; verified legacy flat files are retired after cutover instead of remaining as an unbounded rollback copy. It publishes independently verified snapshot pairs to an ignored folder observed by Dropbox, but the sync client is neither authoritative storage nor complete disaster recovery. It has no public registration, cloud database, or uploads.

## Container View

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73, gray #808080
flowchart TB
    visitor(["Person<br/><b>Family member</b>"])
    admin(["Person<br/><b>Administrator</b>"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Private HTTPS route"}}
    caddy["Container<br/><b>Caddy</b><br/>Loopback blue/green<br/>reverse proxy"]
    codex{{"External system<br/><b>Local Codex installation</b><br/>Codex SDK and app server"}}
    dropbox{{"External system<br/><b>Dropbox sync client</b>"}}

    subgraph bnest["Software system: Bnest"]
        direction TB
        browser["Container<br/><b>Browser / installed PWA</b><br/>HTML, CSS, JavaScript<br/>LiveView client"]
        legacy[("Container / data store<br/><b>Browser legacy sources</b><br/>Allow-listed values<br/>Retained until accepted import")]
        phoenix["Container<br/><b>Phoenix LiveView application</b><br/>Elixir / Phoenix / Bandit"]
        runtime[("Container / data store<br/><b>Local SQLite database</b><br/>Records and schedules<br/>Claims and safe results")]
        backup[("Container / data store<br/><b>Backup folder</b><br/>Owned snapshots<br/>and safe receipts")]
        legacy_runtime[("Container / data store<br/><b>Legacy flat files</b><br/>Migration source<br/>Removed after proof")]
        bridge["Container<br/><b>Codex bridge processes</b><br/>Node.js / Codex SDK and CLI"]

        browser -->|HTTP and WebSocket<br/>events and renders| phoenix
        browser -->|Confirmed<br/>compatibility import| legacy
        phoenix -->|Typed atomic operations| runtime
        phoenix -->|Verified owned pairs| backup
        legacy_runtime -->|Verified migration input| phoenix
        phoenix -->|Ports and JSON lines| bridge
    end

    visitor -->|Uses| browser
    admin -->|Uses admin settings| browser
    tailscale -->|Loopback HTTP<br/>WebSocket| caddy
    caddy -->|Loopback HTTP<br/>WebSocket| phoenix
    bridge -->|Discovers models<br/>runs or resumes threads| codex
    backup -->|Filesystem sync| dropbox

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef container fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor,admin person
    class browser,phoenix,bridge container
    class legacy,runtime,legacy_runtime,backup data
    class tailscale,codex,dropbox external
    class caddy container
```

The Phoenix server, SQLite storage, temporary flat-file migration source, backup folder, and Node bridges run on the home host. Caddy is a separate loopback container between Tailscale and blue/green Phoenix releases. OTP supervision recovers failed child processes inside one running application; replacement starts and proves the alternate release before Caddy promotes it. The stable storage pointer remains at `~/.config/bnest/storage.json`, while the default production database lives at `~/bnest/data/prod/bnest.sqlite3`. A separate private pointer optionally overrides the exact ignored `data/backup/` default. Verified flat sources under `data/prod/` are removed after routed storage proof. Filesystem test fixtures remain in a marked Dropbox run below `data/test/runs/`, while the paired SQLite database uses the same run identifier below `~/bnest/data/test/runs/`; both roots are cleaned after the run.

## Release and Resumable State

The managed release controller serializes each clean `origin/main` revision through one fail-closed transaction. Production slots own `4000` and `4001`, Caddy owns `4100`, isolated E2E leases `4010`–`4019`, and development leases `4020`–`4029`. Every managed slot enables secure cookies and account identity cutover, so a logged-out root request follows the login boundary instead of receiving a synthetic legacy user. The controller creates no artifact until every fixed gate passes, refuses an undeclared migration adapter, and leaves the proven route active when only final cleanup needs retrying. A private release-overlap monitor follows the logged-out root-to-login journey while sampling local Caddy health and the exact routed user surface from preflight through drain; schema-v4 evidence rejects any routed failure, p95 latency above 500 ms, or individual sample above 2 seconds without persisting the private origin.

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73
flowchart TD
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
```

Current chat continuity combines durable server records with LiveView form auto-recovery: a compatible transport reconnect restores the same route, completed or in-progress conversation, Codex session identity, and unsent composer draft without calling `page.reload()`. An in-progress restored turn retains its pending continuation while policy-driven model normalization remains valid; it is never treated as a user model-selection event. Future multiplayer must use the executable continuity contract below; the contract exists now as a tested release fixture, but no multiplayer product is implemented.

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73
flowchart TD
    browser[Browser route and draft] --> gateway[LiveView or Channel]
    browser -->|stable session id| session[Authoritative session]
    gateway -->|resume sequence| session
    session --> events[Ordered event log]
    events -->|catch-up events| browser
    browser -->|idempotent command| session
    presence[Ephemeral presence] -.->|not game truth| session

    classDef client fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    classDef runtime fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef durable fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    class browser client
    class gateway,presence runtime
    class session,events durable
```

## Component View

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73, gray #808080
flowchart TB
    browser(["External container<br/><b>Browser / installed PWA</b>"])
    legacy[("External data store<br/><b>Allow-listed browser sources</b>")]
    bridge{{"External container<br/><b>Codex bridge processes</b>"}}

    subgraph phoenix["Container: Phoenix<br/>LiveView application"]
        direction TB

        identity["Component<br/><b>Identity</b><br/>Bootstrap and login<br/>Sessions and roles"]
        auth["Component<br/><b>Authorization</b><br/>Capability plus ownership checks"]
        repository["Component<br/><b>Data repository</b><br/>Schemas, coordinator<br/>Ecto repo and phase"]
        imports["Component<br/><b>Import and recovery</b><br/>Envelopes and manifests<br/>Retry and restore"]
        settings["Component<br/><b>Admin settings</b><br/>Typed panel registry<br/>Admin-only LiveViews"]
        scheduler["Component<br/><b>Daily scheduler</b><br/>Claims and retries<br/>Lease coordination"]
        tasks["Component<br/><b>Task supervisor</b><br/>Allowlisted handlers"]
        backups["Component<br/><b>Backup proof</b><br/>VACUUM and quick check<br/>Receipts and retention"]

        subgraph chat_area["Chat components"]
            direction LR
            chat_live["Component<br/><b>Chat LiveView</b><br/>BnestAppWeb.ChatLive"]
            chat["Component<br/><b>Chat domain</b><br/>BnestApp.Chat"]
            catalog["Component<br/><b>Model catalog</b><br/>GenServer"]
            access["Component<br/><b>Repository access policy</b><br/>Role-derived sandbox"]
            session["Component<br/><b>Codex session port</b><br/>Session / PortSession"]

            chat_live -->|State transitions| chat
            chat_live -->|Model capabilities| catalog
            chat_live -->|Role and toggle| access
            chat_live -->|Sandbox lifecycle| session
        end

        subgraph learning_area["Learning components"]
            direction LR
            sifat_live["Component<br/><b>Sifat Allah LiveView</b><br/>BnestAppWeb.SifatAllahLive"]
            sifat["Component<br/><b>Sifat Allah domain</b><br/>BnestApp.SifatAllah"]

            sifat_live -->|Learning actions| sifat
        end

        identity --> auth
        identity -->|Accounts and sessions| repository
        auth --> repository
        imports --> repository
        settings --> scheduler
        scheduler -->|Schedule ledger| repository
        scheduler -->|Dispatches claims| tasks
        tasks --> backups
        backups -->|Snapshot source| repository
        chat_live -->|User-owned chat| repository
        sifat_live -->|User-owned progress| repository
    end

    browser -->|Opaque cookie<br/>protected events| identity
    browser -->|Chat events and renders| chat_live
    browser -->|Learning events<br/>renders| sifat_live
    browser -->|Confirmed source values| imports
    browser -->|Admin-only events| settings
    browser -->|Web Storage API<br/>until accepted import| legacy
    session -->|JSON lines| bridge

    classDef external fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef component fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef process fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    class browser external
    class identity,auth,repository,imports,settings,scheduler,tasks,backups,chat_live,chat,catalog,access,session,sifat_live,sifat component
    class bridge process
    class legacy data
```

## Architectural Constraints

- Phoenix binds to blue/green loopback endpoints; Caddy owns the stable loopback route and Tailscale Serve forwards only to Caddy.
- Chat runners default to read-only, retain approval policy `never` and disabled network and web search, and accept only server-derived `read-only` or `workspace-write`. Only an account containing `admin` without `children` can explicitly enable writes; any `children` role wins, parent-only accounts remain read-only, and reconnect or clear resets read-only.
- The chat runner forwards only public reasoning summaries and generic activity status with stable item IDs; raw private reasoning and tool input remain outside the transcript. Chat retains these progress entries beside the final assistant answer across reconnects.
- Every protected route and data operation resolves an unrevoked opaque-cookie session and current user before repository access.
- Bootstrap, username indexes, accounts, and browser sessions use the phase-aware repository; SQLite authority never reads a retired flat identity source.
- Roles may contain `children`, `parents`, and `admin`; capabilities still default-deny cross-user access.
- Codex model access is role-scoped server-side: admins receive the discovered catalog, parents use Terra at medium effort, and children use Luna at medium effort. A missing required model disables that role's chat instead of substituting another model.
- Durable chat, Sifat Allah progress, and explicit theme state live in the authenticated user's SQLite records after accepted import.
- Daily definitions, unique claims, retry state, leases, occurrence expiry, and safe results live in SQLite. One generic coordinator dispatches code-allowlisted handlers from both schedule contexts and never trusts executable names from stored data.
- The production SQLite backup schedule never expires. It verifies a `VACUUM INTO` snapshot through an independent read-only connection, checks the attempt fence before atomic publication, and retains only owned receipt-backed pairs for the latest seven WIB dates.
- Only the exact Git-ignored `data/backup/` path may be used inside the repository. External overrides reject symbolic links, live-source/config overlap, and unsafe repository paths; no route downloads or exposes backup paths or payloads.
- Browser keys are immutable compatibility sources until envelope, normalization, and normal read-back pass; only the accepted key is then cleared.
- Mutable records use revision checks, one path lock coordinated across connected local BEAM release nodes, atomic replacement, and read-back. Sessions have no time expiry and remain independent per browser.
- Test adapters use only synthetic `test-user-` identities and paired marked flat-file and SQLite run roots; production structural audit is read-only.
- Routine releases are clean-revision transactions owning release and resource locks, with fixed uncached gates, capacity and port admission, immutable artifact and migration manifests, revision proofs, rollback, bounded drain, and two-artifact retention. Pre-mutation admission requires normal exported memory pressure, at least 9 GiB available non-compressed estimate, compressor availability, and interval CPU headroom for four release plus two safety units. Final overlap proof requires normal pressure, compressor availability, at least 2 GiB estimated availability, two p95 CPU units, zero local or routed health failures, routed p95 at or below 500 ms, and every routed sample at or below 2 seconds; swap-in or swap-out is pressure only below 4 GiB. Compressor payload remains evidence rather than a fullness ratio. Repository-owned development uses the same collector, a private heavy-work lease, bounded warning/critical shedding, and never signals production, Caddy, or unrelated processes.
- A future multiplayer connection resumes authoritative versioned state by stable session identity, catches up ordered events after its acknowledged sequence, and retries commands by idempotency identity. Server time orders durable actions; presence remains ephemeral.

## Behaviour Traceability

Executable behavior is specified in [`behaviours/`](behaviours/). Unit, local-only integration, and browser E2E adapters must implement that exact recursive corpus.
