# Resource-Aware Development

Apply this to compute-bearing Nx work under `apps/`, `libs/`, and repository tools. It reduces host pressure without guaranteeing survival.

## Required Behavior

- Run this work through the guard. Exit `75` is transient capacity or a held heavy-work lease, not failure: wait, then retry the same command serially from the beginning.
- Confirm the previous run exited; stacked `ephemeral` runs starve admission. Lease deferrals name holders; `service` holds none. "Safe admission was not reached" names none. `resource-guard status` is only a later sample; the newest evidence summary names the deciding signal.
- Never abandon the objective, bypass the guard, retry concurrently, background a retry loop, weaken gates, or change class for admission.
- Exit `73` is storage-blocked. Safely free space before retrying; cooldown cannot fix it.
- Exit `78` means invalid configuration or a strict transactional/release profile mismatch. Replan; do not cooldown-loop it.
- Stable `serve`, managed release, and pre-push enter automatically. Recovery, proxy status, rollback, retire, and tailnet controls remain direct.
- Use `transactional` for a mutation that must not be killed after starting; never to exempt ordinary build or test work.
- The guard signals only the child process group it created, never production Bnest, Caddy, Tailscale, another application, or an unverified PID.

Canonical guarded execution is:

```sh
./resource-guard run --class ephemeral --disk-path . -- npm exec -- nx run -p <project> -t <target>
```

## Admission and Shedding

The guard resolves host and finite cgroup v2 capacity. Ordinary work follows `balanced` → `constrained` → `minimal`; the last uses concurrency one and may admit below its static reserve when pressure is not critical. Transactions and releases stay strict.

| Profile       | Memory reserve     | No-swap reserve    | Disk reserve      | CPU admission |
| ------------- | ------------------ | ------------------ | ----------------- | ------------- |
| `balanced`    | 15%, 1–4 GiB       | 20%, 1–4 GiB       | 10%, 2–20 GiB     | 85%           |
| `constrained` | 10%, 512 MiB–2 GiB | 15%, 512 MiB–2 GiB | 5%, 1–8 GiB       | 92%           |
| `minimal`     | 5%, 128–512 MiB    | 10%, 256–768 MiB   | 2%, 256 MiB–1 GiB | 98%           |

Percentages clamp to the table. Disk below the immutable 256 MiB floor exits `73`. No Linux swap is supported evidence. Per fifteen seconds, swap-out warning/critical rates are 0.4%/1.6% of memory, clamped to 64–128 MiB and 256–512 MiB. macOS compressor payload/growth ratios are 37.5%/3.125% warning and 50%/6.25% critical. Linux PSI warns at `some avg10 >= 10%`; `some >= 25%`, `full >= 5%`, or new OOM is critical.

Admission requires normal evidence, except balanced Darwin ephemeral work may admit after 15 stable warning seconds with 25% available memory (4–8 GiB clamp), balanced CPU/disk headroom, and no OOM or warning-level swap/compressor growth; tool concurrency is forced to one. Services, fallbacks, Linux PSI, transactions, and releases are excluded. Unsafe warning gets ten seconds for ephemeral and thirty for services; critical pressure sheds immediately. Storage shedding exits `73`; other shedding exits `75`. Transactions record pressure but complete.

The `./resource-guard` bootstrap and `resource-guard.lock` pin an immutable, checksummed release from the public [resource-guard repository](https://github.com/wahidyankf/resource-guard). Source, executable specifications, and enforcement live upstream; Beaver Nest owns only its pin, bootstrap behavior, machine-policy example, and product-specific invocation. Copy `./resource-guard.local.json.example` to the ignored `resource-guard.local.json` for machine policy. `--config`, `RESOURCE_GUARD_CONFIG`, then that file apply in order, and cannot weaken compiled safety floors.

## Evidence Basis

XNU maps internal memory state to normal `1`, warning `2`, and critical `4` flags before exposing the sysctl ([XNU conversion](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c), [dispatch flags](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/main/dispatch/source.h)). XNU describes available non-compressed memory as an estimate from active, inactive, free, and speculative pages, not free RAM ([memory-status model](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md)). XNU compressor accounting shows payload bytes are not a compressor-capacity percentage ([compressor implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_compressor.c)).

## Evidence and Cleanup

The collector normalizes CPU, memory, pressure, swap, disk, RSS, and health. Linux uses `/proc`, PSI, and cgroup v2; macOS keeps pressure/compressor evidence.

Samples use schema v3; release summaries use v5. They default to `~/Library/Application Support/resource-guard/` on macOS and `${XDG_STATE_HOME:-$HOME/.local/state}/resource-guard/` on Linux; samples expire in seven days, summaries in thirty, and files stay below 50 MiB. Evidence stores the config hash and profile, never contents, arguments, origins, paths, credentials, or user data. Retained schema-v2 through schema-v4 release summaries remain readable.

Verify changes through guarded resource-guard Nx targets, affected guarded gates, and the repository gate. Use deterministic fake pressure in tests; never endanger the host to prove shedding.
