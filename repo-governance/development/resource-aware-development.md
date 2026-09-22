# Resource-Aware Development

[HIPPO](https://github.com/wahidyankf/hippo) guards local Nx compute without guaranteeing survival. Its source,
specifications, protocol, and releases stay upstream. BeaverNest owns its pin, bootstrap, local policy, mappings, and
invocations.

## Execution Contract

Give local compute exactly one guard with a disk path:

```sh
./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p <project> -t <target>
```

Targets owning a service or port lease own the guard; callers never wrap them again. Recovery and status stay direct.

Use `ephemeral` for repeatable work, `service` for development servers, and `transactional` for indivisible mutations.
Every class consumes fixed capacity; never change class for priority.

Choose tiers independently: `light` for narrow static checks, `standard` for ordinary work, and `heavy` for full builds,
suites, and gates. Schema 3 keeps one FIFO waiter, grants the largest safe vector, and launches at most once.

Independent DAG nodes may overlap through HIPPO. Preserve dependencies, shared-output edges, ordered stages,
migrations, build state, ports, transactions, locks, and proven serialization.

## Reservations and Recovery

Schema 3 shares one reservation ledger. CPU and memory fit atomically; healthy evidence may promote two base owners to
three. Later waiters never bypass the FIFO head.

Children receive immutable `HIPPO_CONCURRENCY` and `HIPPO_RESERVED_MEMORY_BYTES`. The wrapper maps CPU only to
`NX_PARALLEL`, `GOMAXPROCS`, and `DOTNET_PROCESSOR_COUNT`; missing values receive it, smaller values survive, larger ones
clamp, and malformed values fail.

A status says what to do; the `hippo: [hippo.area.reason]` line on stderr says which case. Two
reasons under one status can need opposite responses, so read both.

- Exit `124` is a limit stopping the work. `hippo.limit.storage-blocked` means safely free space
  first, since waiting frees no disk. `hippo.limit.capacity-deferred` is retryable only when a new
  schema-1 receipt proves `never-started`; a pressure shed or a `started-safety-stop` requires
  payload-specific recovery.
- Exit `125` means HIPPO started nothing. `hippo.coordination.protocol-mismatch` is a peer protocol
  mismatch: never retry it; inspect `./hippo status`, then drain or upgrade the incompatible client.
  `hippo.policy.replan-required` and the `hippo.config.*` reasons mean invalid configuration, an
  impossible reservation, an invalid mapping, or a strict profile mismatch. Replan rather than
  cooldown-loop.
- Exit `2` means the invocation itself is unusable. Read the diagnostic and fix the command.
- Exit `126` and `127` mean the guarded command cannot be executed, or is not there.
- Exit `1` means the work ran and the answer is empty: a result, never a capacity signal.

Child codes pass through, including ones colliding with a status HIPPO uses; only HIPPO's own
failures write that `hippo:` line, and without a new `never-started` receipt a code stays
child-owned.

`hippo.lock` pins identity, not semantics. Before changing behaviour, read the Hippo repository at the commit in
`hippo.lock`, then align rules, Gherkin, and checks with its documented capabilities. Never infer capability from SemVer
or copy release numbers into governance.

Critical pressure sheds eligible ephemeral, then service owners; transactions are last at the emergency floor. Only the
owning guard signals, reaps, and releases its child.

## Enforcement

An unguarded sibling Nx fan-out once forced a host restart. HIPPO cannot shed unknown work.

[The boundary hook](../../.claude/hooks/require-hippo-boundary.sh) rejects unguarded compute before spawn. All three
harnesses bind the shared byte-identical hook.

It checks presence, not class judgment, and matches compute verbs only in command position.

## Configuration, Evidence, and Verification

Copy [`hippo.local.json.example`](../../hippo.local.json.example) to ignored `hippo.local.json`. `--config` overrides
`HIPPO_CONFIG`, then the bootstrap default. A worktree without a local copy inherits the primary checkout's policy.

`hippo.identity.json` labels shared queue and history from nested paths and contained `worktrees/<task>` checkouts. Add
privacy-safe `--tag checkout=worktree --tag plan=<slug>` values. Use `./hippo status`,
`./hippo watch --source beaver-nest`, and `./hippo history --since 30d --source beaver-nest` directly.
Use one platform root; set `HIPPO_ROOT` only for isolated tests. Evidence excludes arguments, origins, paths,
credentials, contents, and user data. Raw evidence rolls for seven days;
compacted daily summaries roll for 30 days under byte caps.

Verify wrapper changes with its bootstrap suite, guarded Nx checks, and repository gate. Test pressure synthetically.
