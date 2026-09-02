# Resource-Aware Development

Apply this standard to compute-bearing Nx work under `apps/`, `libs/`, and repository-owned tools. It reduces macOS or Linux pressure without controlling unrelated applications or guaranteeing host survival.

## Required Behavior

- Run compute-bearing Nx work through the guard. Exit `75` is transient capacity, not task or test failure: wait for recovery, then retry the same command serially from the beginning.
- Confirm the previous guarded run has exited before retrying. Stacked `ephemeral` runs queue for one admission slot and starve each other, producing no output for minutes; that silence is contention, not a hung target, and must never be answered with another concurrent run. Check with `ps` and read `resource-guard status`, whose `state=normal` proves capacity is not the constraint.
- Never abandon the objective, bypass the guard, retry concurrently, background a retry loop, weaken gates, or change class for admission.
- Exit `73` is storage-blocked. Safely free space before retrying; cooldown cannot fix it.
- Exit `78` means invalid configuration or a strict transactional/release profile mismatch. Replan; do not cooldown-loop it.
- The stable development `serve`, managed release, and pre-push hook enter the guard automatically. Recovery, proxy status, rollback, retire, and tailnet controls remain directly available.
- Use `transactional` admission for storage mutation or another command that must not be killed after starting. Never use that class to exempt ordinary build or test work.
- The guard may signal only the child process group it created. It must never stop production Bnest, Caddy, Tailscale, another application, or an unverified PID.

Canonical guarded execution is:

```sh
apps/resource-guard/resource-guard run --class ephemeral --disk-path . -- npm exec -- nx run -p <project> -t <target>
```

The plugin-free `resource-guard` project owns Nx targets. Its POSIX bootstrap executes a content-addressed Go binary so admission precedes Node and Nx. Repository agents retain the required `rtk` prefix. Use `service` only for a non-production server and `transactional` only for an admitted mutation.

## Admission and Shedding

The guard resolves effective memory and CPU capacity from the host and finite cgroup v2 limits. Ordinary work follows `balanced` → `constrained` → `minimal`; the final profile uses concurrency one and still attempts admission when static estimates are below its reserve but actual pressure is not critical. Transactional and release work keep their requested profile strict.

| Profile       | Memory reserve     | No-swap reserve    | Disk reserve      | CPU admission |
| ------------- | ------------------ | ------------------ | ----------------- | ------------- |
| `balanced`    | 15%, 1–4 GiB       | 20%, 1–4 GiB       | 10%, 2–20 GiB     | 85%           |
| `constrained` | 10%, 512 MiB–2 GiB | 15%, 512 MiB–2 GiB | 5%, 1–8 GiB       | 92%           |
| `minimal`     | 5%, 128–512 MiB    | 10%, 256–768 MiB   | 2%, 256 MiB–1 GiB | 98%           |

The percentage is clamped to the stated range. Disk below the immutable 256 MiB floor exits `73`. Linux without usable swap is a supported capability state, not invalid evidence. Swap-out warning/critical rates are clamped to 0.4%/1.6% of effective memory with 64–128 MiB and 256–512 MiB bounds per fifteen seconds. macOS compressor payload and growth use 37.5%/3.125% warning and 50%/6.25% critical ratios. Linux memory PSI warns at `some avg10 >= 10%` and is critical at `some >= 25%`, `full >= 5%`, or a new OOM event.

Critical pressure sheds ordinary work immediately. Warning grace is ten seconds for ephemeral work and thirty for development serve. Storage shedding exits `73`; other shedding exits `75`. Transactional work records post-start pressure but completes safely.

Local machine policy may be copied from `apps/resource-guard/resource-guard.local.json.example` to the ignored `resource-guard.local.json`. CLI `--config`, `RESOURCE_GUARD_CONFIG`, and the repository-local file are checked in that order. Strict JSON overrides cannot weaken compiled safety floors.

## Evidence Basis

XNU maps internal memory state to exported dispatch-compatible normal `1`, warning `2`, and critical `4` flags before exposing the sysctl ([XNU conversion](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c), [dispatch flags](https://github.com/swiftlang/swift-corelibs-libdispatch/blob/main/dispatch/source.h)). XNU describes available non-compressed memory as an estimate derived from active, inactive, free, and speculative pages, so the guard does not call it free RAM ([memory-status model](https://github.com/apple-oss-distributions/xnu/blob/main/doc/vm/memorystatus_notify.md)). XNU compressor accounting shows payload bytes are not a compressor-capacity percentage ([compressor implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_compressor.c)).

## Evidence and Cleanup

The collector normalizes CPU, effective memory, pressure capabilities, swap state, disk, RSS, and applicable health evidence. Linux uses `/proc`, PSI, and cgroup v2; macOS keeps memory-pressure and compressor evidence. Compressor payload is not a fullness percentage.

Samples use schema v3; release summaries use v4. They default to `~/bnest/runtime/resource-guard/`; samples expire in seven days, summaries in thirty, and files stay below 50 MiB. Evidence stores the config hash and profile, never contents, arguments, origins, paths, credentials, or user data. Schema-v2/v3 release summaries remain readable during retention.

Verify changes through guarded resource-guard Nx targets, affected guarded Nx gates, and the repository gate. Use deterministic fake pressure in tests; never endanger the host to prove shedding.
