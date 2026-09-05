# Resource-Aware Development

**HIPPO** — **H**ost **I**nfrastructure **P**ressure & **P**rocess **O**rchestrator — guards
compute-bearing Nx work under `apps/`, `libs/`, and repository tools without guaranteeing survival.
The independent public [HIPPO repository](https://github.com/wahidyankf/hippo) owns its source,
specifications, thresholds, coordination protocol, and releases. Never copy or fork those assets
here. BeaverNest owns only its checksum pin, thin bootstrap, local policy example, mappings, and
invocations.

## Execution Contract

Give every local compute command exactly one outer guard with an explicit disk path:

```sh
./hippo run --class ephemeral --disk-path . -- npm exec -- nx run -p <project> -t <target>
```

A target that must acquire a service or port lease owns that boundary; callers invoke the Nx target
without wrapping it again. Recovery, proxy status, rollback, retirement, and tailnet controls remain
direct so admission cannot block recovery.

Use `ephemeral` for ordinary build and test work, `service` for a non-production server, and
`transactional` only for a mutation that must not be killed after it starts. Every class consumes a
fixed CPU-and-memory allocation. Never change class to obtain admission.

Independent repository and project DAG nodes may overlap only through HIPPO admission. Preserve Nx
dependencies, shared-output writer/reader edges, ordered target stages, migrations, .NET/Mix build
state, E2E port ownership, managed-release transactions, storage locks, and every other proven
correctness serialization.

## Reservations and Recovery

Schema-2 policy enables one shared reservation ledger for all repositories using the same
`HIPPO_ROOT`. CPU and memory fit atomically. Admission is strict FIFO: a smaller later waiter cannot
bypass the head. `balanced`, `constrained`, and `minimal` automatic allocations divide available
capacity across four, two, and one owner shares. Every live owner and waiter contributes its owner
limit; the strictest live value applies.

An admitted child receives immutable `HIPPO_CONCURRENCY` and `HIPPO_RESERVED_MEMORY_BYTES`. The
BeaverNest wrapper maps concurrency, in order, to exactly `NX_PARALLEL`, `GOMAXPROCS`, and
`DOTNET_PROCESSOR_COUNT`. Missing mappings receive allocated CPU, lower positive caller values
survive, higher values clamp, and malformed values require replanning. No fourth consumer mapping is
allowed.

- Exit `75` defers or sheds one invocation. Read its reason, wait for that condition, and retry only
  the same command. Never create duplicate or background retry loops; unrelated admitted work may
  continue.
- Exit `73` is storage-blocked. Safely free space before retrying.
- Exit `78` means invalid configuration, impossible reservation, invalid mapping, or a strict
  profile mismatch. Replan rather than cooldown-loop.

Critical pressure selects the newest eligible ephemeral owner, then a service only when none remain.
Transactional owners are never shed after admission. Only the guard that owns a child may signal,
reap, and release it; production services, Caddy, and unrelated processes are outside that boundary.

## Configuration, Evidence, and Verification

Copy [`hippo.local.json.example`](../../hippo.local.json.example) to ignored `hippo.local.json` for
machine policy. `--config` overrides `HIPPO_CONFIG`, which overrides the bootstrap default. The
schema-2 example uses reservation mode, a maximum of twenty active owners, automatic 4/2/1 shares,
and a constrained custom profile without an artificial one-worker cap.

State defaults to the platform HIPPO state directory; `HIPPO_ROOT` may select one shared private
root. Evidence is bounded and excludes arguments, origins, paths, credentials, contents, and user
data. Consumers use documented JSON and summary schemas, never runtime coordination files.

Verify wrapper changes with `.github/scripts/test-hippo-bootstrap.sh`, then run the narrowest guarded
Nx gates, affected guarded quick graph, and repository gate. Use isolated roots and deterministic
synthetic pressure; never endanger the host to prove admission or shedding.
