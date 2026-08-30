# Technical Design

## Entry Point

Add a root `apps/resource-guard/` module set with collector, policies, private evidence, verified session lease, child supervisor, and CLI. Canonical Nx targets remain the public task interface; stable serve, managed release, npm test entry points, and pre-push enter automatically, while other compute-bearing targets use the documented wrapper.

## Measurements

- Normalize CPU utilization to 0–100 from deltas of `os.cpus().times`; retain no `ps` aggregate gate.
- Name `memory_pressure -Q` output `availableNonCompressedEstimateBytes` and parse it fail-closed.
- Use `kern.memorystatus_vm_pressure_level` and `vm.compressor_available` as hard platform state.
- Keep compressor payload, VM pages, swap-in/out, swap usage, RSS, disk, and health as evidence without inventing fullness semantics.

## Policies

- Development admission: normal pressure, compressor available, at least 9 GiB estimate, and CPU utilization leaving two execution units idle for three consecutive samples inside 15 seconds.
- Critical: exported critical pressure, compressor unavailable, invalid essential reading, or estimate below 4 GiB.
- Ephemeral warning grace is 10 seconds; development serve warning grace is 30 seconds. Critical sheds immediately.
- Release retains its existing disk and final memory/health rules, replaces CPU sampling with normalized deltas, removes the 37.5% compressor-payload hard gate, and records schema version 2.

## Process Lifecycle

A private machine-local lease serializes heavy sessions across shells. Nested invocations inherit a nonce that is accepted only while its owner marker identifies a live process. The guard spawns a detached child process group, forwards ordinary signals, sends `SIGTERM` on shedding, waits ten seconds, and then sends `SIGKILL` only to that group. Capacity outcomes use exit 75.

Recovery, status, proxy, and tailnet operations remain unguarded. Storage mutation uses admission-only protection. Managed release owns an exclusive resource session and bypasses nested gate wrappers only through its verified session.

## Evidence

Default root is `~/bnest/runtime/resource-guard/`, private directories are `0700`, and files are `0600`. Raw samples live seven days, summaries thirty days, and total evidence is capped at 50 MiB by oldest-first cleanup. No command arguments, origins, application paths, credentials, or user data are recorded.

## Public Interfaces

- `beaver-nest:resource:status` prints a safe snapshot and supports `--json`.
- `beaver-nest:resource:monitor` prints state transitions until interrupted.
- `beaver-nest:resource:test` runs deterministic collector and guard tests.
- `npm run resource:run -- --class <class> -- <command>` guards other compute-bearing Nx commands without shell interpolation.

## Specification Changes

Update Bnest architecture and release documentation to describe exported pressure state, normalized CPU, compressor availability, evidence-only compressor payload, and the development guard. No application Gherkin changes are required because browser/runtime behavior is unchanged.

## File Impact

- `[N] apps/resource-guard/**`: shared collector, policy, CLI, process lifecycle, and tests.
- `[E] package.json`, project target definitions, and `.husky/pre-push`: Nx entry-point wiring and bounded parallelism.
- `[E] apps/bnest-app/tools/release.mjs`, resource monitor, release tests, and serve launcher: shared metrics and guarded lifecycle.
- `[E] AGENTS.md`, Nx task skill, development governance/map, Bnest README, and architecture specification: canonical rule and truthful documentation.
- `[E] plans/in-progress/**`: delivery tracking, evidence, and final archive move.

## Verification and Continuity

Use deterministic fakes for pressure and signals; never create real host pressure. Run focused tool, release, affected quick, repository, and isolated E2E gates. Check routed health before and after material work. No production cutover is required because application runtime behavior does not change.
