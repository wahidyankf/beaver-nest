# Resource-Aware Development

**HIPPO** — **H**ost **I**nfrastructure **P**ressure & **P**rocess **O**rchestrator — guards
compute-bearing Nx work under `apps/`, `libs/`, and repository tools without guaranteeing survival.
The independent public [HIPPO repository](https://github.com/wahidyankf/hippo) owns its source,
specifications, thresholds, coordination protocol, and releases. Never copy or fork those assets
here. BeaverNest owns only its checksum pin, thin bootstrap, local policy example, mappings, and
invocations.

## Execution Contract

Give local compute exactly one guard with a disk path:

```sh
./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p <project> -t <target>
```

A target that must acquire a service or port lease owns that boundary; callers invoke the Nx target
without wrapping it again. Recovery, proxy status, rollback, retirement, and tailnet controls remain
direct so admission cannot block recovery.

Use `ephemeral` for ordinary build and test work, `service` for a non-production server, and
`transactional` only for a mutation that must not be killed after it starts. Every class consumes a
fixed CPU-and-memory allocation. Never change class to obtain admission.

Choose a resource tier independently: `light` for narrow static checks, `standard` for ordinary
checks and writers, and `heavy` for full builds, full suites, browser suites, and complete gates.
Schema 3 keeps one FIFO waiter, grants the largest safe vector within the tier, and starts the
payload at most once.

Independent repository and project DAG nodes may overlap only through HIPPO admission. Preserve Nx
dependencies, shared-output writer/reader edges, ordered target stages, migrations, .NET/Mix build
state, E2E port ownership, managed-release transactions, storage locks, and every other proven
correctness serialization.

## Reservations and Recovery

Schema-3 policy enables one shared reservation ledger for every repository and worktree using the
default root. CPU and memory fit atomically. A two-owner base may promote to three only after the
configured healthy overlapping evidence. A smaller later waiter cannot bypass the FIFO head.

An admitted child receives immutable `HIPPO_CONCURRENCY` and `HIPPO_RESERVED_MEMORY_BYTES`. The
BeaverNest wrapper maps concurrency, in order, to exactly `NX_PARALLEL`, `GOMAXPROCS`, and
`DOTNET_PROCESSOR_COUNT`. Missing mappings receive allocated CPU, lower positive caller values
survive, higher values clamp, and malformed values require replanning. No fourth consumer mapping is
allowed.

- Exit `75` requires its receipt or outcome. Requeue only `never-started`; pressure-shed,
  storage-shed, and `started-safety-stop` require payload-specific recovery. Never create duplicate
  or background retry loops; unrelated admitted work may continue.
- Exit `73` is storage-blocked. Safely free space before retrying.
- Exit `78` means invalid configuration, impossible reservation, invalid mapping, or a strict
  profile mismatch. Replan rather than cooldown-loop.

Ordinary critical pressure selects the newest eligible ephemeral owner, then a service. A
transactional owner is eligible last only at the configured emergency floor. Only the guard that
owns a child may signal, reap, and release it; production services, Caddy, and unrelated processes
are outside that boundary.

## Enforcement

The contract above was prose only, and prose did not hold: an unguarded Nx fan-out in a sibling
repository forced a host restart. HIPPO cannot shed work it was never told about, so pressure went
critical while the scheduler still reported `normal`.

[`.claude/hooks/require-hippo-boundary.sh`](../../.claude/hooks/require-hippo-boundary.sh) refuses a
compute-bearing command carrying no outer guard, before the process spawns. All three harnesses bind
it, byte-identical to every other consuming repository's copy so a fix cannot miss one.

It decides only whether a guard is present, never which class is right. Verbs match only in command
position, so searching for a verb string is not refused. A verb reached through an interpreter or a
Mix alias is not in command position and still passes.

## Configuration, Evidence, and Verification

Copy [`hippo.local.json.example`](../../hippo.local.json.example) to ignored `hippo.local.json` for
machine policy. `--config` overrides `HIPPO_CONFIG`, which overrides the bootstrap default. The
schema-3 example documents the shared pool, owner gate, resource tiers, deadlines, promotion gate,
and emergency floor. A contained worktree with no local copy uses the primary checkout's ignored
policy.

`hippo.identity.json` labels BeaverNest in the shared queue and bounded history. Hippo discovers it
from nested directories and contained `worktrees/<task>` checkouts; add privacy-safe
`--tag checkout=worktree --tag plan=<slug>` overrides per run. Use `./hippo status`,
`./hippo watch --source beaver-nest`, and `./hippo history --since 30d --source beaver-nest` directly.
State defaults to one platform root; set `HIPPO_ROOT` only for isolated tests. Evidence excludes
arguments, origins, paths, credentials, contents, and user data.

Verify wrapper changes with `.github/scripts/test-hippo-bootstrap.sh`, then run the narrowest guarded
Nx gates, affected guarded quick graph, and repository gate. Use isolated roots and deterministic
synthetic pressure; never endanger the host to prove admission or shedding.
