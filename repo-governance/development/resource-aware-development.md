# Resource-Aware Development

Apply this standard to compute-bearing Nx work under `apps/`, `libs/`, and repository-owned tools. It reduces measured host pressure; it neither controls unrelated applications nor guarantees macOS cannot restart.

## Required Behavior

- Run compute-bearing Nx work through the guard. Exit `75` is transient capacity, not task or test failure: wait for recovery, then retry the same command serially from the beginning.
- Never abandon the objective, bypass the guard, retry concurrently, weaken gates, or change class for admission.
- Exit `73` means storage-blocked. Safely free space before retrying; cooldown alone cannot remediate it.
- The stable development `serve`, managed release, and pre-push hook enter the guard automatically. Recovery, proxy status, rollback, retire, and tailnet controls remain directly available.
- Use `transactional` admission for storage mutation or another command that must not be killed after starting. Never use that class to exempt ordinary build or test work.
- The guard may signal only the child process group it created. It must never stop production Bnest, Caddy, Tailscale, another application, or an unverified PID.

Canonical guarded execution is:

```sh
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p <project> -t <target>
```

The plugin-free `resource-guard` project owns lifecycle targets. Root `resource:status`, `resource:monitor`, and `resource:run` remain direct Node bootstrap entry points so admission precedes Nx. Repository agents retain the required `rtk` prefix. Use `service` only for a non-production long-running server and `transactional` only for an admitted mutation.

## Admission and Shedding

Admission requires normal macOS pressure, an available compressor, at least 9 GiB available non-compressed estimate, at least 30 GiB disk free, and three CPU samples preserving two execution units. Missing or lower disk headroom immediately exits `73`. Lease wait is five minutes; transient admission wait is fifteen seconds.

| Signal             | Warning                                      | Critical                                     |
| ------------------ | -------------------------------------------- | -------------------------------------------- |
| Memory estimate    | Below 9 GiB                                  | Below 4 GiB                                  |
| Disk free          | Below 30 GiB                                 | Below 20 GiB                                 |
| Swap-out           | 128 MiB normalized per fifteen seconds       | 512 MiB normalized per fifteen seconds       |
| Compressor payload | 12 GiB and growing 1 GiB per fifteen seconds | 16 GiB and growing 2 GiB per fifteen seconds |

Critical pressure, compressor unavailability, or invalid essential readings shed ordinary work immediately. Warning grace is ten seconds for ephemeral work and thirty for development serve. Storage shedding exits `73`; other shedding exits `75`. CPU affects admission only. Transactional work records pressure but completes safely.

Swap-out converts rolling page deltas to bytes using sampled page size. Persistent swap usage and stable compressor payload are evidence only.

These numbers are Bnest host-local policy, not Apple, Node, or Erlang standards. Recalibrate after hardware, RAM, macOS, or representative workload changes.

## Evidence Basis

XNU maps internal memory state to exported dispatch-compatible normal `1`, warning `2`, and critical `4` flags before exposing the sysctl ([XNU conversion](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c), [dispatch flags](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/main/dispatch/source.h)). XNU describes available non-compressed memory as an estimate derived from active, inactive, free, and speculative pages, so the guard does not call it free RAM ([memory-status model](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md)). Node exposes cumulative per-CPU time counters suitable for interval deltas and separately defines available parallelism as a scheduling estimate, not idle cores ([Node OS API](https://nodejs.org/api/os.html)). XNU compressor accounting shows payload bytes are not a compressor-capacity percentage ([compressor implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_compressor.c)).

## Evidence and Cleanup

The collector derives CPU from cumulative CPU-time deltas and records pressure, compressor, available estimate, VM, swap, disk, RSS, and applicable health evidence. Compressor payload is not a fullness percentage.

Private evidence defaults to `~/bnest/runtime/resource-guard/`. Raw samples expire after seven days, summaries after thirty, and files remain below 50 MiB total. Evidence excludes arguments, origins, application paths, credentials, and user data.

Verify changes through `resource-guard:test`, affected guarded Nx gates, and the repository gate. Use deterministic fake pressure in tests; never endanger the host to prove shedding.
