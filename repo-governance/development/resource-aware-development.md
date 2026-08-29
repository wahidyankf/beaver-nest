# Resource-Aware Development

Apply this standard to every current or future Nx project under `apps/` and `libs/`, plus repository-owned tools. It covers development commands that compile, build, lint, test, run coverage, execute E2E, validate the repository, or start a development server. It reduces this host's measured memory-pressure risk; it does not control unrelated applications or prove that macOS cannot restart.

## Required Behavior

- Run compute-bearing Nx work through the resource guard. Treat exit `75` as temporary capacity deferral or pressure shedding; wait for recovery instead of bypassing it or retrying concurrently.
- The stable development `serve`, managed release, and pre-push hook enter the guard automatically. Recovery, proxy status, rollback, retire, and tailnet controls remain directly available.
- Use `transactional` admission for storage mutation or another command that must not be killed after starting. Never use that class to exempt ordinary build or test work.
- The guard may signal only the child process group it created. It must never stop production Bnest, Caddy, Tailscale, another application, or an unverified PID.

Canonical guarded execution is:

```sh
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p <project> -t <target>
```

Repository agents additionally retain the required `rtk` prefix. Use `service` only for a non-production long-running server and `transactional` only for an admitted mutation.

## Admission and Shedding

Admission requires exported macOS memory pressure to be normal, the compressor to report available, the available non-compressed estimate to remain at least 9 GiB, and three interval CPU samples to preserve two execution units. A protected task waits at most five minutes for the heavy-work lease and fifteen seconds for capacity.

Critical pressure, compressor unavailability, an invalid essential reading, or an estimate below 4 GiB sheds ordinary guarded work immediately. A warning sustained for ten seconds sheds ephemeral work; development serve receives thirty seconds. CPU affects admission only and never sheds running work. Transactional work records pressure but remains responsible for its own safe completion.

These numbers are Bnest host-local policy, not Apple, Node, or Erlang standards. Recalibrate after hardware, RAM, macOS, or representative workload changes.

## Evidence Basis

XNU maps internal memory state to exported dispatch-compatible normal `1`, warning `2`, and critical `4` flags before exposing the sysctl ([XNU conversion](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c), [dispatch flags](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/main/dispatch/source.h)). XNU describes available non-compressed memory as an estimate derived from active, inactive, free, and speculative pages, so the guard does not call it free RAM ([memory-status model](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md)). Node exposes cumulative per-CPU time counters suitable for interval deltas and separately defines available parallelism as a scheduling estimate, not idle cores ([Node OS API](https://nodejs.org/api/os.html)). XNU compressor accounting shows payload bytes are not a compressor-capacity percentage ([compressor implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_compressor.c)).

## Evidence and Cleanup

The shared collector derives CPU from cumulative CPU-time deltas. It records exported pressure, compressor availability, an explicitly named available non-compressed estimate, compressor payload, VM pages, swap-in/out and free space, disk, RSS, and applicable health latency. Compressor payload is evidence, never a fullness percentage.

Development evidence defaults to private `~/bnest/runtime/resource-guard/` state. Raw samples expire after seven days, summaries after thirty days, and total files remain below 50 MiB. Evidence contains no command arguments, origins, application paths, credentials, or user data.

Verify changes through `beaver-nest:resource:test`, affected guarded Nx gates, and the repository gate. Use deterministic fake pressure in tests; never endanger the host to prove shedding.
