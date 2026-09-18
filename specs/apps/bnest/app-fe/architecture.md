# Bnest Frontend Architecture

This is the canonical as-built C4 model for Bnest's frontend surface: routes and rendered UI, the installable PWA,
browser-owned compatibility storage, and responsive/accessible presentation. Maintain it under the repository
[architecture specification standard](../../../../repo-governance/development/architecture-specifications.md). The
backend surface is documented separately at [`app-be/architecture.md`](../app-be/architecture.md); both surfaces are
delivered by the one running `bnest-app` process and are aggregated by [`specs/apps/bnest/README.md`](../README.md).

## System Context

```mermaid
flowchart TB
    visitor(["Person<br/><b>Family member</b><br/>Uses the private<br/>family application"])
    admin(["Person<br/><b>Administrator</b><br/>Manages schedules<br/>and backup settings"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Private HTTPS route<br/>to stable local proxy"}}
    caddy["Container<br/><b>Caddy</b><br/>Loopback reverse proxy<br/>Blue/green upstream drain"]
    frontend[["Software system<br/><b>Bnest frontend</b><br/>Rendered routes<br/>Installable PWA"]]
    backend{{"External system<br/><b>Bnest backend</b><br/>See app-be/architecture.md"}}
    webpush{{"External system<br/><b>Browser-vendor<br/>Web Push service</b><br/>Delivers push events<br/>to the service worker"}}

    visitor -->|Remote HTTPS / WebSocket| tailscale
    tailscale -->|Loopback HTTP| caddy
    caddy -->|Loopback HTTP<br/>WebSocket| frontend
    visitor -.->|Direct home-host<br/>connection| frontend
    admin -->|Private admin UI| frontend
    frontend -->|HTTP and WebSocket<br/>events, session cookie| backend
    webpush -.->|Push event<br/>to service worker| frontend

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef system fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor,admin person
    class frontend system
    class tailscale,backend,webpush external
    class caddy system
```

The frontend surface is the one place family members and administrators interact with Bnest: every rendered route,
LiveView, and browser asset. It renders through the same Phoenix process that hosts [`app-be`](../app-be/architecture.md);
the split here is by observable contract, not by a second deployed system. Elixir/Phoenix LiveView was selected so
server-rendered HTML and a persistent WebSocket connection stay authoritative without a separate client-side data
store. Caddy promotes a healthy blue or green Phoenix release with a bounded WebSocket drain; compatible LiveView
clients reconnect without a manual refresh. The compatibility revision adds a family chat room route that is
GraphQL-driven rather than LiveView-driven (see [Component View](#component-view)), and a service-worker push
subscription that, once granted, receives notifications directly from the browser vendor's Web Push service —
a delivery path that never crosses Tailscale Serve or Caddy. Both are implemented and tested behind the
`BNEST_FAMILY_CHAT_ENABLED` flag, which still defaults to off in this revision.

## Container View

```mermaid
flowchart TB
    visitor(["Person<br/><b>Family member</b>"])
    admin(["Person<br/><b>Administrator</b>"])
    tailscale{{"External system<br/><b>Tailscale Serve</b><br/>Private HTTPS route"}}
    caddy["Container<br/><b>Caddy</b><br/>Loopback blue/green<br/>reverse proxy"]
    backend{{"External container<br/><b>Phoenix backend domain</b><br/>See app-be/architecture.md"}}
    webpush{{"External system<br/><b>Web Push service</b>"}}

    subgraph frontend["Software system: Bnest frontend"]
        direction TB
        browser["Container<br/><b>Browser / installed PWA</b><br/>HTML, CSS, JavaScript<br/>LiveView client"]
        legacy[("Container / data store<br/><b>Browser legacy sources</b><br/>Allow-listed values<br/>Retained until accepted import")]
        routes["Container<br/><b>Phoenix route/LiveView shell</b><br/>Renders rendered UI<br/>over the backend boundary"]
        worker["Container<br/><b>Service worker</b><br/>App-shell cache<br/>Push permission and events<br/>IndexedDB outbox"]

        browser -->|HTTP and WebSocket<br/>events and renders| routes
        browser -->|Confirmed<br/>compatibility import| legacy
        browser -->|Registers and<br/>posts messages| worker
    end

    visitor -->|Uses| browser
    admin -->|Uses admin settings| browser
    tailscale -->|Loopback HTTP<br/>WebSocket| caddy
    caddy -->|Loopback HTTP<br/>WebSocket| routes
    routes -->|Domain calls| backend
    worker -->|Push event| webpush

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef container fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class visitor,admin person
    class browser,routes,worker container
    class legacy data
    class tailscale,backend,webpush external
    class caddy container
```

The route/LiveView shell runs inside the same Phoenix OTP application as the backend domain; it is drawn as its own
container here because it is this surface's canonical observable boundary, not because it is a separately deployed
process. Phoenix binds to blue/green loopback endpoints; Caddy owns the stable loopback route and Tailscale Serve
forwards only to Caddy. The service worker (`service-worker.js` and `assets/js/family_chat/*`) is a distinct
browser-owned container: it keeps the offline app-shell cache, holds the bounded per-room IndexedDB send outbox with
backoff/seven-day-expiry, and owns the push-permission prompt and incoming `push` event handling, independent of
whether the family chat route is currently open.

## Component View

```mermaid
flowchart TB
    browser(["External container<br/><b>Browser / installed PWA</b>"])
    worker(["External container<br/><b>Service worker</b>"])
    legacy[("External data store<br/><b>Allow-listed browser sources</b>")]
    backend{{"External container<br/><b>Phoenix backend domain</b>"}}

    subgraph routes["Container: Phoenix<br/>route/LiveView shell"]
        direction LR
        chat_live["Component<br/><b>Chat LiveView</b><br/>BnestAppWeb.ChatLive"]
        sifat_live["Component<br/><b>Sifat Allah LiveView</b><br/>BnestAppWeb.SifatAllahLive"]
        home["Component<br/><b>Home/auth routes</b><br/>Login, setup, redirects"]
        admin_ui["Component<br/><b>Admin settings UI</b><br/>Storage, schedules"]
        importer["Component<br/><b>Browser import UI</b><br/>data-migration route"]
        family_chat["Component<br/><b>Family chat route</b><br/>FamilyChatController,<br/>not a LiveView"]

        chat_live -->|Chat/learning events| backend
        sifat_live -->|Chat/learning events| backend
        home -->|Auth events| backend
        admin_ui -->|Admin events| backend
        importer -->|Confirmed source values| backend
        family_chat -->|Renders shell,<br/>then browser owns it| backend
    end

    browser -->|Chat events and renders| chat_live
    browser -->|Learning events<br/>renders| sifat_live
    browser -->|Protected events| home
    browser -->|Admin-only events| admin_ui
    browser -->|Confirmed source values| importer
    browser -->|Web Storage API<br/>until accepted import| legacy
    browser -->|Initial page load| family_chat
    browser -->|GraphQL ops<br/>over UserSocket| backend
    browser <-->|Outbox, cache,<br/>push permission| worker
    worker -->|Displays notification| browser

    classDef external fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef component fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef data fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    class browser,worker external
    class chat_live,sifat_live,home,admin_ui,importer,family_chat component
    class legacy data
    class backend external
```

The family chat route renders only the initial page shell (room list/composer scaffold); once loaded, the browser
drives every subsequent read, send, and live update itself over GraphQL directly against
[`app-be`](../app-be/architecture.md)'s schema and `UserSocket`, bypassing the LiveView event pattern the other
routes use. The service worker is drawn as a second external container here (not a `routes` component) because it
runs independently of any open route: it can display a push notification, extend the offline app-shell cache, or
retry a queued outbox entry while no family chat tab is open.

## Architectural Constraints

- Chat runners default to read-only, retain approval policy `never` and disabled network and web search, and accept
  only server-derived `read-only` or `workspace-write`. Only an account containing `admin` without `children` can
  explicitly enable writes; any `children` role wins, parent-only accounts remain read-only, and reconnect or clear
  resets read-only.
- The chat runner forwards only public reasoning summaries and generic activity status with stable item IDs; raw
  private reasoning and tool input remain outside the transcript. Chat retains these progress entries beside the
  final assistant answer across reconnects.
- Committed transcript, learning progress, and theme are never authoritative in browser storage; they are rendered
  from the backend's SQLite records after accepted import.
- Browser keys are immutable compatibility sources until envelope, normalization, and normal read-back pass; only
  the accepted key is then cleared from the browser.
- A logged-out request to `/` redirects to `/login`, so protected home actions never render without a session.
  One-time `/setup` creates every initial account and permanently closes; `/login` then protects family data. There
  is no public registration or password-recovery flow.
- The root layout links a standalone PWA manifest and Beaver Nest icon sizes for Android, desktop Chromium browsers,
  and Apple home-screen use. The service worker keeps a cached application shell as an offline fallback while
  preferring the live app whenever the home host is reachable, and never caches authenticated data.
- Every Bnest interface uses the Nest workshop visual language defined by the `--bnest-*` tokens in
  [`assets/css/app.css`](../../../../apps/bnest-app/assets/css/app.css); reuse those tokens rather than adding
  page-local colors, fonts, corner treatments, or shadows.
- Current chat continuity combines durable server records with LiveView form auto-recovery: a compatible transport
  reconnect restores the same route, completed or in-progress conversation, and unsent composer draft without
  calling `page.reload()`.
- Family chat never caches authenticated room or message content in the service worker; only the static app shell is
  cached offline. A dropped GraphQL subscription reconnects with capped backoff, catches up through
  `family_chat_messages`, and survives a Caddy blue/green promotion the same way LiveView clients do.
  Session/authentication expiry pauses the connection instead of retrying against an unauthenticated socket, and a
  logout in one tab never affects another tab's independent session.
- The IndexedDB send outbox is bounded per room and expires unsent entries after seven days, resuming delivery on
  reconnect/online transitions; Web Push permission is requested only from an explicit user gesture, never on page
  load, and the browser can revoke it at any time without breaking the room.
- Family chat's message list keeps a scroll anchor on new arrivals and announces new messages through a live region,
  and its layout, like every Bnest surface, is responsive and accessible at the viewports this repository tests.

## Behaviour Traceability

Executable frontend behaviour is specified in [`behaviours/`](behaviours/). `bnest-app`'s unit and local-only
integration adapters, aggregated with [`app-be`](../app-be/architecture.md)'s root, must implement that exact
recursive corpus; `bnest-app-fe-e2e` implements this root's E2E adapter alone.
