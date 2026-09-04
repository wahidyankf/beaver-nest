# Resource-Aware Development

Apply this to compute-bearing Nx work under `apps/`, `libs/`, and repository tools. It reduces host pressure without guaranteeing survival.

## Required Behavior

- Run this work through the guard. Exit `75` is transient capacity or a held heavy-work lease, not failure: wait, then retry the same command serially from the beginning.
- Confirm the previous run exited; stacked `ephemeral` runs starve admission. Lease deferrals name holders. For admission evidence, read the newest summary rather than a later `status` sample.
- Never abandon the objective, bypass the guard, retry concurrently, background a retry loop, weaken gates, or change class for admission.
- Exit `73` is storage-blocked. Safely free space before retrying; cooldown cannot fix it.
- Exit `78` means invalid configuration or a strict transactional/release profile mismatch. Replan; do not cooldown-loop it.
- Stable `serve`, managed release, and pre-push enter automatically. Recovery, proxy status, rollback, retire, and tailnet controls remain direct.
- Use `transactional` for a mutation that must not be killed after starting; never to exempt ordinary build or test work.
- The guard signals only its child process group, never production services or an unverified PID.

Canonical guarded execution is:

```sh
./resource-guard run --class ephemeral --disk-path . -- npm exec -- nx run -p <project> -t <target>
```

Upstream exports canonical `RESOURCE_GUARD_PROFILE` and `RESOURCE_GUARD_CONCURRENCY` values. This wrapper maps concurrency to `NX_PARALLEL`, `GOMAXPROCS`, and `DOTNET_PROCESSOR_COUNT` through repeatable `--concurrency-env` flags. Ordinary admission preserves caller values; degraded admission forces selected mappings to one. The consumer owns these ecosystem choices, so upstream stays generic.

## Admission and Shedding

The guard resolves host and finite cgroup v2 capacity. Ordinary work follows `balanced` → `constrained` → `minimal`; the last uses concurrency one and may admit below its static reserve when pressure is not critical. Transactions and releases stay strict.

| Profile       | Memory reserve     | No-swap reserve    | Disk reserve      | CPU admission |
| ------------- | ------------------ | ------------------ | ----------------- | ------------- |
| `balanced`    | 15%, 1–4 GiB       | 20%, 1–4 GiB       | 10%, 2–20 GiB     | 85%           |
| `constrained` | 10%, 512 MiB–2 GiB | 15%, 512 MiB–2 GiB | 5%, 1–8 GiB       | 92%           |
| `minimal`     | 5%, 128–512 MiB    | 10%, 256–768 MiB   | 2%, 256 MiB–1 GiB | 98%           |

Percentages clamp to the table. Disk below 256 MiB exits `73`; no Linux swap is valid evidence. Over fifteen seconds, swap-out warning/critical rates are 0.4%/1.6% of memory with 64–128 MiB and 256–512 MiB clamps. macOS payload/growth ratios are 37.5%/3.125% warning and 50%/6.25% critical. Linux PSI warns at `some avg10 >= 10%`; `some >= 25%`, `full >= 5%`, or new OOM is critical.

Admission requires normal evidence, except balanced Darwin ephemeral work may admit after 15 stable warning seconds with 25% available memory (4–8 GiB clamp), balanced CPU/disk headroom, and no OOM or warning-level swap/compressor growth; canonical concurrency and the wrapper-selected tool mappings are forced to one. Services, fallbacks, Linux PSI, transactions, and releases are excluded. Unsafe warning gets ten seconds for ephemeral and thirty for services; critical pressure sheds immediately. Storage shedding exits `73`; other shedding exits `75`. Transactions record pressure but complete.

The bootstrap and lock pin a checksummed release from the public [resource-guard repository](https://github.com/wahidyankf/resource-guard), which owns source, specifications, and enforcement. Beaver Nest owns its pin, wrapper, policy example, and invocations. Copy the example to ignored `resource-guard.local.json` for machine policy. Precedence is `--config`, `RESOURCE_GUARD_CONFIG`, then that file; none can weaken safety floors.

## Evidence Basis

XNU exposes normal `1`, warning `2`, and critical `4` memory states ([conversion](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c), [flags](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/main/dispatch/source.h)). Available non-compressed memory estimates active, inactive, free, and speculative pages rather than free RAM ([model](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md)); compressor payload is not a capacity percentage ([implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_compressor.c)).

## Evidence and Cleanup

The collector normalizes CPU, memory, pressure, swap, disk, RSS, and health. Linux uses `/proc`, PSI, and cgroup v2; macOS keeps pressure/compressor evidence.

Samples use schema v3; release summaries use v5. State defaults to `~/Library/Application Support/resource-guard/` on macOS and `${XDG_STATE_HOME:-$HOME/.local/state}/resource-guard/` on Linux. Samples expire in seven days, summaries in thirty, and files stay below 50 MiB. Evidence excludes contents, arguments, origins, paths, credentials, and user data. Summary schemas v2–v4 remain readable.

Verify changes through guarded resource-guard Nx targets, affected guarded gates, and the repository gate. Use deterministic fake pressure in tests; never endanger the host to prove shedding.
