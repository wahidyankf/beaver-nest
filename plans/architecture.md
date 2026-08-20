# Architecture

## System overview

```mermaid
flowchart LR
  Family[Family device<br/>Tailscale installed]
  URL[Private HTTPS URL<br/>wkf-desktop...ts.net]
  Serve[Tailscale Serve]

  subgraph Host[Always-on home host]
    Phoenix[Phoenix LiveView endpoint]
    Data[(Private Postgres volume)]
    Files[(Private document volume)]
    Worker[Supervised document worker]
    Python[Allowlisted Python processor]

    Phoenix <--> Data
    Phoenix --> Worker
    Worker <--> Data
    Worker <--> Files
    Worker --> Python
  end

  Family --> URL --> Serve --> Phoenix
```

## Responsibilities

| Component | Responsibility |
| --- | --- |
| Phoenix LiveView | HTML UI, real-time browser state, roles, application actions, and job status |
| Elixir/OTP supervisor | Starts and restarts recoverable application workers |
| Document worker | Claims jobs, invokes approved processor programs, validates output, and records result |
| Python processor | Performs a bounded document conversion, extraction, or analysis task |
| Postgres | Private relational data, users, permissions, document metadata, and job state |
| Private document volume | Original uploads, staging, and accepted processor output |
| Tailscale Serve | Private HTTPS endpoint and requester identity forwarding |

## Document-processing flow

```mermaid
sequenceDiagram
  participant B as Family browser
  participant P as Phoenix LiveView
  participant D as Data and files
  participant W as Supervised worker
  participant X as Python processor

  B->>P: Upload document
  P->>D: Store private staged input
  P->>W: Enqueue durable job
  P-->>B: Render queued/running status
  W->>X: Invoke allowlisted executable
  X-->>W: Bounded output and exit status
  W->>D: Save validated result and job state
  W-->>P: Publish status update
  P-->>B: Render completion or failure
```

## Security boundaries

- Phoenix listens only on localhost; Tailscale Serve is the only external route.
- Tailscale establishes network identity; Phoenix maps it to application roles and record-level permissions.
- The document worker accepts a fixed job schema, not a command from the browser.
- External programs use absolute executable paths and argument lists, never a shell command.
- Processors run with least privilege: restricted filesystem access, resource limits, no outbound network, and a dedicated staging/output area.
- Data volumes are outside the Git and Dropbox workspace.
