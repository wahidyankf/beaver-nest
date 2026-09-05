# Glossary

Terms used across Beaver Nest's rules, plans, projects, and commit messages. Each entry gives a plain meaning and links to the canonical document that owns the detail; this page never restates a rule.

## Execution and capacity

- **HIPPO** — Host Infrastructure Pressure & Process Orchestrator; the wrapper every compute-bearing Nx command runs through, so work is admitted only when the host has capacity. See [resource-aware development](../../repo-governance/development/resource-aware-development.md).
- **Class** — what kind of work is being admitted: `ephemeral` for ordinary build and test work, `service` for a non-production server, `transactional` for a mutation that must not be killed once started. Never changed to get admitted.
- **Profile** — how much headroom the guard reserves. Ordinary work falls back `balanced` → `constrained` → `minimal`; transactional and release work keep their requested profile strictly.
- **Reservation** — one atomic CPU-and-memory request against the shared HIPPO root. Every admitted class consumes reservation capacity.
- **Allocation** — the fixed CPU-and-memory vector an admitted invocation receives; worker mappings cannot exceed its CPU value.
- **Waiter** — one deferred invocation holding its FIFO position until capacity fits or its bounded wait expires.
- **Exit 75** — a retryable deferral or shed outcome for one invocation. Do not duplicate it; wait for its stated condition, then retry that same command.
- **Exit 73** — storage-blocked. Free space before retrying; waiting cannot fix it.
- **Exit 78** — invalid configuration or a strict-profile mismatch. Replan rather than retry.
- **`rtk`** — the token-optimized CLI proxy that repository agents prefix onto shell commands. See [RTK instructions](../../RTK.md).
- **Badakmini** — the repository's documentation validator. `badakmini-cli:test:repo` checks directory maps, Markdown links, word budgets, and Mermaid accessibility.

## Testing

- **Behaviour corpus** — the complete set of `.feature` files under `specs/apps/bnest/app/behaviours/`, discovered recursively and treated as one body. A behaviour is described once here, not once per test layer.
- **Adapter** — a layer that binds the corpus to a runtime: Elixir unit and integration adapters in the application project, a browser adapter in the end-to-end project. An adapter that cannot drive a scenario is explicitly exempted rather than given a duplicate scenario.
- **Quick gate** — `test:quick`, the fail-fast sequence of typecheck, lint, unit tests, and behaviour coverage. `test:e2e` is deliberately excluded because browser tests are slow.
- **Red–green–refactor** — one behaviour increment: a failing test, the smallest change that passes it, then a design improvement with tests still green. See [the workflow](../../repo-governance/workflows/red-green-refactor.md).
- **Test identity** — a synthetic account whose username starts with `test-user-`. Real accounts are never used for testing. See [test identities](../../repo-governance/development/test-identities.md).
- **Marked run root** — the isolated pair of directories a test run owns, one flat-file and one SQLite, carrying the same run marker. A mismatched or shared root fails closed.
- **Exploratory pass / usability pass** — two separate manual passes over a running UI: the first spec-aware and probing edges, the second structurally spec-blind and judging first-time perception. See [the workflow](../../repo-governance/workflows/exploratory-and-usability-testing.md).

## Live service

- **Active route** — the path a household member actually reaches, through Caddy and the tailnet. Work is judged against this, not against a local port.
- **Exact origin** — the precise scheme, host, and port a user hits. Evidence gathered anywhere else does not count.
- **Candidate** — an independent backend prepared on an inactive slot while the current one keeps serving. Nothing is promoted before its candidate proves revision, readiness, and a connected journey.
- **Promotion** — switching Caddy's upstream to the candidate with a graceful reload. The only sanctioned way to change what the route serves.
- **Drain** — the bounded period after promotion during which existing WebSocket clients reconnect before the previous backend is retired. A compatible release never requires a manual refresh.
- **Revision** — which build the routed backend is actually serving. A commit or push changes history only; it is not a deployment and is not proof of a revision.
- **Responsiveness budget** — the routed sampling target: zero failures, p95 at or below 500 ms, and every sample at or below 2 seconds, unless a plan states a tighter one. See [live-service continuity](../../repo-governance/development/live-service-continuity.md).
- **Rollback trigger** — the named condition that returns the route to the last healthy backend. Recovery steps stay dormant until their trigger fires, then are reconciled with evidence.

## Data and storage

- **Record type / record key** — how a stored record is addressed: its kind, and its identifier within that kind. Together they are the primary key in `bnest_records`.
- **Owner** — the user a record belongs to, or absent for a system record.
- **Schema version** — the shape version of a stored payload, so an older instance can still read a record during a rolling release.
- **Revision (record)** — an optimistic concurrency counter on a stored record. Writing with a stale revision fails instead of overwriting a concurrent change. Distinct from a deployed **revision** above.
- **Expand, migrate, verify, contract** — the four ordered steps of a data migration: add the new path beside the old, copy with checked identity, read back through the normal product flow, then retire the old path after a stated window. See [plan migrations](../../repo-governance/conventions/plan-migrations.md).

## Planning and governance

- **Plan lifecycle** — `ideas/` → `backlogs/` → `in-progress/` → `done/`. A plan moves; it is never copied between stages. See [the convention](../../repo-governance/conventions/plan-lifecycle.md).
- **`[AI]` / `[HUMAN]`** — who executes a delivery task. `[HUMAN]` is only for a decision, credential, physical action, or authority unavailable to an agent, never to postpone discovery.
- **Blocking checkpoint** — the task that ends a delivery phase. Later phases do not start until it passes.
- **Rules propagation** — the workflow that keeps a changed rule consistent everywhere it is referenced. See [the workflow](../../repo-governance/workflows/rules-propagation.md).
- **Directory map** — the `## Directory Map` section every governed README carries, listing each direct sibling with a relative link. See [the convention](../../repo-governance/conventions/directory-maps.md).
- **Diátaxis** — the four-way split this `docs/` tree follows: tutorials, how-to guides, reference, explanation. See [documentation architecture](../../repo-governance/conventions/documentation-architecture.md).
- **Thematic commit** — a commit scoped to one coherent theme rather than one mechanical batch. See [the convention](../../repo-governance/conventions/thematic-commits.md).
