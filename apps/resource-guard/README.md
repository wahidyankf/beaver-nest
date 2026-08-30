# resource-guard

`resource-guard` is the repository bootstrap application for adaptive macOS and Linux admission, pressure monitoring, heavy-work serialization, port leases, private evidence, child-process supervision, and release resource checks. It understands finite cgroup v2 memory, swap, and CPU limits. It controls only the process group it starts and never stops unrelated or production processes.

The production runtime is Go. The Go module belongs at this project root; there is intentionally no nested `package.json` and no Nx language plugin. Nx owns development lifecycle targets, while the POSIX [`resource-guard`](resource-guard) bootstrap remains the canonical runtime entry so admission happens before Node or Nx starts.

## Usage

Run from the repository root. Repository agents retain the required `rtk` prefix.

| Purpose                 | Command                                                                                                                        |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Inspect host state      | `apps/resource-guard/resource-guard status --json --disk-path .`                                                               |
| Monitor transitions     | `apps/resource-guard/resource-guard monitor --disk-path .`                                                                     |
| Guard an Nx task        | `apps/resource-guard/resource-guard run --class ephemeral --disk-path . -- npm exec -- nx run -p <project> -t <target>`        |
| Guard a transaction     | `apps/resource-guard/resource-guard run --class transactional --disk-path . -- <command>`                                      |
| Run fast project checks | `apps/resource-guard/resource-guard run --class ephemeral --disk-path . -- npm exec -- nx run -p resource-guard -t test:quick` |

Exit `75` means transient capacity: wait for cooling down, then retry the identical guarded command serially. Exit `73` means storage admission or shedding: inspect and clean storage before retrying. Exit `78` means an explicit strict profile or configuration requires replanning. None authorizes bypassing the guard, weakening a gate, parallel retry, or abandoning the objective.

## Bootstrap and artifacts

The bootstrap uses the platform's SHA-256 and `stat` commands to build a content-addressed binary below ignored `.cache/<goos>-<goarch>/<hash>/`. A directory lock serializes builds; compilation uses `GOMAXPROCS=2`, `go build -p=1 -trimpath`, a temporary output, and atomic rename. Retention keeps the current plus two recent generations. E2E binaries are temporary. `dist/`, `.cache/`, `coverage/`, the active `resource-guard.local.json`, and compiled binaries never belong in Git; the tracked `resource-guard` file is the POSIX bootstrap script.

## Quality gates

The canonical Gherkin corpus is [`specs/apps/resource-guard/behaviours`](../../specs/apps/resource-guard/behaviours/README.md). A shared contract uses Godog's parser, an exact reviewed exemption inventory with reasons, and strict step resolution for unit, integration, and compiled-binary E2E adapters. Compliance rejects missing features, scenarios without explicit `When` and `Then`, undefined or ambiguous steps, unused bindings, unknown exemptions, and exemption drift. The three adapter checks run serially through commands declared in this project's `project.json`.

| Target             | Contract                                                                                                 |
| ------------------ | -------------------------------------------------------------------------------------------------------- |
| `typecheck`        | Compile every package and test without running scenarios.                                                |
| `build:platforms`  | Cross-build Darwin/Linux on amd64/arm64 without retaining binaries.                                      |
| `lint`             | Run every available pinned Go linter and formatter with documented project-local exceptions.             |
| `security`         | Scan reachable dependency and standard-library code for known vulnerabilities.                           |
| `test:unit`        | Run deterministic policy and unit Gherkin cases.                                                         |
| `test:integration` | Exercise local files, leases, evidence, processes, and integration Gherkin cases without network.        |
| `test:e2e`         | Build a temporary public binary, exercise it safely, and remove it on every exit.                        |
| `test:artifacts`   | Reject tracked local config or binaries and preserve the committable example.                            |
| `test:coverage`    | Enforce numeric production coverage at 99% and all three behavior compliance adapters.                   |
| `test:quick`       | Run typecheck, lint, unit, numeric coverage, and all compliance adapters; full integration/E2E stay out. |
| `test`             | Run unit, integration, coverage/compliance, and the full temporary-binary E2E suite serially.            |

System-call adapters, process boundaries, and the thin `main` entry are exercised through integration or compiled-binary E2E. Deterministic policy, profile, strict-config, and macOS/Linux parser logic is enumerated under the 99% numeric gate.

## Resource policy

Ordinary work resolves `balanced` → `constrained` → `minimal` from effective memory, available memory, disk, CPU, and swap capability. `minimal` uses concurrency one and avoids rejecting a small runner solely from a static estimate. Transactional and release work are strict and exit `78` rather than silently downgrading. Linux PSI and new OOM events, macOS pressure/compressor trends, swap-out rate, and the 256 MiB hard disk floor remain active safety signals.

Copy [`resource-guard.local.json.example`](resource-guard.local.json.example) to the ignored `resource-guard.local.json` for machine-local profile selection or stricter limits. `--config` overrides `RESOURCE_GUARD_CONFIG`, which overrides that local file. Unknown fields, duplicates, cycles, unsafe floors, and unsupported schemas fail with exit `78`. Evidence is schema 3; schema-2 release summaries remain readable during retention.

## Structure

- `cmd/resource-guard/` is the thin executable entry.
- `internal/cli/` owns argument validation and output.
- `internal/config/` loads strict machine-local profile overrides.
- `internal/host/` normalizes macOS, Linux, cgroup, swap, and PSI metrics.
- `internal/policy/` owns pure development and release decisions.
- `internal/guard/` owns evidence, leases, and child supervision.
- `internal/release/` owns release checks, monitoring, and summary assessment.
- `tests/contract/` owns the shared strict suite configuration, binding registry, and compliance policy.
- `tests/support/` keeps thin Gherkin bindings separate from the scenario driver implementation.
- `tests/unit/`, `tests/integration/`, and `tests/e2e/` contain the three adapters; E2E remains inside this project.
- `tests/coverage/` enforces numeric production coverage.
- `project.json` defines the plugin-free Nx lifecycle.

See [resource-aware development](../../repo-governance/development/resource-aware-development.md) for the canonical agent procedure.
