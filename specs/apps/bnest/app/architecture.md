# Bnest Architecture

This is the canonical as-built C4 model for Bnest. Maintain it under the repository [architecture specification standard](../../../../repo-governance/development/architecture-specifications.md).

## System Context

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, gray #808080
flowchart TB
    visitor(["Person<br/><b>Family member</b><br/>Uses the private family application"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Private HTTPS route to the stable local proxy"}}
    caddy["Container<br/><b>Caddy</b><br/>Loopback reverse proxy with blue/green upstream drain"]
    bnest[["Software system<br/><b>Bnest</b><br/>Authenticated family experiences with centralized local data"]]
    codex{{"External system<br/><b>Local Codex installation</b><br/>Model discovery and read-only Codex threads"}}

    visitor -->|Remote HTTPS / WebSocket| tailscale
    tailscale -->|Loopback HTTP| caddy
    caddy -->|Loopback HTTP / WebSocket| bnest
    visitor -.->|Direct connection on home host| bnest
    bnest -->|Local processes| codex

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef system fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor person
    class bnest system
    class tailscale,codex external
    class caddy system
```

Bnest is a 24/7 family service, private to the local host and family devices routed through Tailscale Serve and a stable loopback Caddy proxy. Caddy promotes a healthy blue or green Phoenix release with a bounded WebSocket drain; compatible LiveView clients reconnect without a manual refresh. Elixir/OTP and Phoenix were selected for supervision, process isolation, and concurrent long-lived LiveView sessions. Approved users authenticate before protected access. Bnest keeps user-owned state in a server-managed flat-file runtime root; it has no public registration, cloud database, or uploads.

## Container View

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73, gray #808080
flowchart TB
    visitor(["Person<br/><b>Family member</b>"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Private HTTPS route"}}
    caddy["Container<br/><b>Caddy</b><br/>Loopback blue/green reverse proxy"]
    codex{{"External system<br/><b>Local Codex installation</b><br/>Codex SDK and app server"}}

    subgraph bnest["Software system: Bnest"]
        direction TB
        browser["Container<br/><b>Browser / installed PWA</b><br/>HTML, CSS, JavaScript, LiveView client"]
        legacy[("Container / data store<br/><b>Browser legacy sources</b><br/>Allow-listed values retained only until accepted import")]
        phoenix["Container<br/><b>Phoenix LiveView application</b><br/>Elixir / Phoenix / Bandit"]
        runtime[("Container / data store<br/><b>Runtime flat files</b><br/>Accounts, sessions, manifests, and user-owned records")]
        bridge["Container<br/><b>Codex bridge processes</b><br/>Node.js / Codex SDK and CLI"]

        browser -->|HTTP / WebSocket events and renders| phoenix
        browser -->|Confirmed compatibility import| legacy
        phoenix -->|Typed atomic operations| runtime
        phoenix -->|Ports and JSON lines| bridge
    end

    visitor -->|Uses| browser
    tailscale -->|Loopback HTTP / WebSocket| caddy
    caddy -->|Loopback HTTP / WebSocket| phoenix
    bridge -->|Discovers models; runs or resumes threads| codex

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef container fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor person
    class browser,phoenix,bridge container
    class legacy,runtime data
    class tailscale,codex external
    class caddy container
```

The Phoenix server, runtime repository, and Node bridges run on the home host. Caddy is a separate loopback container between Tailscale and blue/green Phoenix releases. OTP supervision recovers failed child processes inside one running application; replacement starts and proves the alternate release before Caddy promotes it. Production resolves `data/prod/` once before supervision; filesystem tests use one marked mirror below `data/test/runs/`.

## Component View

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73, gray #808080
flowchart TB
    browser(["External container<br/><b>Browser / installed PWA</b>"])
    legacy[("External data store<br/><b>Allow-listed browser sources</b>")]
    bridge{{"External container<br/><b>Codex bridge processes</b>"}}

    subgraph phoenix["Container: Phoenix LiveView application"]
        direction TB

        identity["Component<br/><b>Identity</b><br/>Bootstrap, Argon2id login, sessions, roles"]
        auth["Component<br/><b>Authorization</b><br/>Capability plus ownership checks"]
        repository["Component<br/><b>Data repository</b><br/>Schemas, paths, locks, atomic writes"]
        imports["Component<br/><b>Import and recovery</b><br/>Envelopes, manifests, retry, restore"]

        subgraph chat_area["Chat components"]
            direction LR
            chat_live["Component<br/><b>Chat LiveView</b><br/>BnestAppWeb.ChatLive"]
            chat["Component<br/><b>Chat domain</b><br/>BnestApp.Chat"]
            catalog["Component<br/><b>Model catalog</b><br/>GenServer"]
            session["Component<br/><b>Codex session port</b><br/>Session / PortSession"]

            chat_live -->|State transitions| chat
            chat_live -->|Model capabilities| catalog
            chat_live -->|Session lifecycle| session
        end

        subgraph learning_area["Learning components"]
            direction LR
            sifat_live["Component<br/><b>Sifat Allah LiveView</b><br/>BnestAppWeb.SifatAllahLive"]
            sifat["Component<br/><b>Sifat Allah domain</b><br/>BnestApp.SifatAllah"]

            sifat_live -->|Learning actions| sifat
        end

        identity --> auth
        auth --> repository
        imports --> repository
        chat_live -->|User-owned chat| repository
        sifat_live -->|User-owned progress| repository
    end

    browser -->|Opaque cookie and protected events| identity
    browser -->|Chat events and renders| chat_live
    browser -->|Learning events and renders| sifat_live
    browser -->|Confirmed source values| imports
    browser -->|Web Storage API until accepted import| legacy
    session -->|JSON lines| bridge

    classDef external fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef component fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef process fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    class browser external
    class identity,auth,repository,imports,chat_live,chat,catalog,session,sifat_live,sifat component
    class bridge process
    class legacy data
```

## Architectural Constraints

- Phoenix binds to blue/green loopback endpoints; Caddy owns the stable loopback route and Tailscale Serve forwards only to Caddy.
- Chat runners use read-only sandbox access, approval policy `never`, and disabled network and web search.
- Every protected route and data operation resolves an unrevoked opaque-cookie session and current user before repository access.
- Roles may contain `children`, `parents`, and `admin`; capabilities still default-deny cross-user access.
- Durable chat, Sifat Allah progress, and explicit theme state live only below the authenticated user's runtime path after accepted import.
- Browser keys are immutable compatibility sources until envelope, normalization, and normal read-back pass; only the accepted key is then cleared.
- Mutable records use revision checks, one path lock coordinated across connected local BEAM release nodes, atomic replacement, and read-back. Sessions have no time expiry and remain independent per browser.
- Test adapters use only synthetic `test-user-` identities and marked mirrored runtime roots; production structural audit is read-only.

## Behaviour Traceability

Executable behavior is specified in [`behaviours/`](behaviours/). Unit, local-only integration, and browser E2E adapters must implement that exact recursive corpus.
