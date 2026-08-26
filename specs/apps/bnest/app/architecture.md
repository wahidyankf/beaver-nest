# Bnest Architecture

This is the canonical as-built C4 model for Bnest. Maintain it under the repository [architecture specification standard](../../../../repo-governance/development/architecture-specifications.md).

## System Context

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, gray #808080
flowchart TB
    visitor(["Person<br/><b>Family member</b><br/>Uses the private family application"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Optional private HTTPS route to the home host"}}
    bnest[["Software system<br/><b>Bnest</b><br/>Local Codex chat and browser-persisted learning activities"]]
    codex{{"External system<br/><b>Local Codex installation</b><br/>Model discovery and read-only Codex threads"}}

    visitor -->|Remote HTTPS / WebSocket| tailscale
    tailscale -->|Loopback proxy| bnest
    visitor -.->|Direct connection on home host| bnest
    bnest -->|Local processes| codex

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef system fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor person
    class bnest system
    class tailscale,codex external
```

Bnest is private to the local host and family devices routed through the independently managed Tailscale proxy. It has no application database, authentication, uploads, or server-side user-data store.

## Container View

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73, gray #808080
flowchart TB
    visitor(["Person<br/><b>Family member</b>"])
    codex{{"External system<br/><b>Local Codex installation</b><br/>Codex SDK and app server"}}

    subgraph bnest["Software system: Bnest"]
        direction TB
        browser["Container<br/><b>Browser / installed PWA</b><br/>HTML, CSS, JavaScript, LiveView client"]
        storage[("Container / data store<br/><b>Browser storage</b><br/>sessionStorage and localStorage")]
        phoenix["Container<br/><b>Phoenix LiveView application</b><br/>Elixir / Phoenix / Bandit"]
        bridge["Container<br/><b>Codex bridge processes</b><br/>Node.js / Codex SDK and CLI"]

        browser -->|HTTP / WebSocket events and renders| phoenix
        browser -->|Web Storage API| storage
        phoenix -->|Ports and JSON lines| bridge
    end

    visitor -->|Uses| browser
    bridge -->|Discovers models; runs or resumes threads| codex

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef container fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor person
    class browser,phoenix,bridge container
    class storage data
    class codex external
```

The Phoenix server and Node bridges run on the home host. Tailscale Serve may proxy the browser connection but has an independent lifecycle. Each connected chat LiveView owns one bridge process; a supervised catalog performs model discovery at application startup.

## Component View

```mermaid
%% Accessible palette: blue #0173B2, orange #DE8F05, teal #029E73, gray #808080
flowchart TB
    browser(["External container<br/><b>Browser / installed PWA</b>"])
    storage[("External data store<br/><b>Browser snapshots</b>")]
    bridge{{"External container<br/><b>Codex bridge processes</b>"}}

    subgraph phoenix["Container: Phoenix LiveView application"]
        direction TB

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
    end

    browser -->|Chat events, renders, and snapshots| chat_live
    browser -->|Learning events, renders, and snapshots| sifat_live
    browser -->|Web Storage API| storage
    session -->|JSON lines| bridge

    classDef external fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef component fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef process fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    class browser external
    class chat_live,chat,catalog,session,sifat_live,sifat component
    class bridge process
    class storage data
```

## Architectural Constraints

- Phoenix binds to the local endpoint lifecycle; Tailscale Serve is optional and managed independently.
- Chat runners use read-only sandbox access, approval policy `never`, and disabled network and web search.
- Completed chat state stays in the current browser tab's `sessionStorage`; Sifat Allah progress stays in browser `localStorage`.
- The application owns no database, authentication, cross-device history, uploads, or server-side user-data persistence.
- Test adapters replace live Codex discovery and chat sessions with deterministic local fixtures.

## Behaviour Traceability

Executable behavior is specified in [`behaviours/`](behaviours/). Unit, local-only integration, and browser E2E adapters must implement that exact recursive corpus.
