# resource-guard

`resource-guard` is the repository bootstrap application for macOS host admission, pressure monitoring, heavy-work serialization, port leases, private evidence, child-process supervision, and release resource checks. It controls only the process group it starts and never stops unrelated or production processes.

The production runtime is Go. The Go module belongs at this project root; there is intentionally no nested `package.json` and no Nx language plugin. Nx owns development lifecycle targets, while the POSIX [`resource-guard`](resource-guard) bootstrap remains the canonical runtime entry so admission happens before Node or Nx starts.

## Usage

Run from the repository root. Repository agents retain the required `rtk` prefix.

| Purpose                 | Command                                                                                                                         |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Inspect host state      | `tools/resource-guard/resource-guard status --json --disk-path .`                                                               |
| Monitor transitions     | `tools/resource-guard/resource-guard monitor --disk-path .`                                                                     |
| Guard an Nx task        | `tools/resource-guard/resource-guard run --class ephemeral --disk-path . -- npm exec -- nx run -p <project> -t <target>`        |
| Guard a transaction     | `tools/resource-guard/resource-guard run --class transactional --disk-path . -- <command>`                                      |
| Run fast project checks | `tools/resource-guard/resource-guard run --class ephemeral --disk-path . -- npm exec -- nx run -p resource-guard -t test:quick` |

Exit `75` means transient capacity: wait for cooling down, then retry the identical guarded command serially. Exit `73` means storage admission or shedding: inspect and clean storage before retrying. Neither code authorizes bypassing the guard, weakening a gate, parallel retry, or abandoning the objective.

## Bootstrap and artifacts

The bootstrap hashes `cmd/`, `internal/`, `go.mod`, and `go.sum`, then builds a content-addressed binary below ignored `.cache/<goos>-<goarch>/<hash>/`. A directory lock serializes concurrent builds; compilation uses `GOMAXPROCS=2`, `go build -p=1 -trimpath`, a temporary output, and atomic rename. Retention keeps the current generation plus the two most recently used historical generations. The Nx build target deliberately disables output caching, while E2E compiles into an automatically removed temporary directory. `dist/`, `.cache/`, and `coverage/` are ignored; no compiled binary belongs in Git.

## Quality gates

The canonical Gherkin corpus is [`specs/tools/resource-guard/behaviours`](../../specs/tools/resource-guard/behaviours/README.md). A shared contract uses Godog's parser, an exact reviewed exemption inventory with reasons, and strict step resolution for unit, integration, and compiled-binary E2E adapters. Compliance rejects missing features, scenarios without explicit `When` and `Then`, undefined or ambiguous steps, unused bindings, unknown exemptions, and exemption drift. The three adapter checks run serially through commands declared in this project's `project.json`.

| Target             | Contract                                                                                                 |
| ------------------ | -------------------------------------------------------------------------------------------------------- |
| `typecheck`        | Compile every package and test without running scenarios.                                                |
| `lint`             | Run every available pinned Go linter and formatter with documented project-local exceptions.             |
| `security`         | Scan reachable dependency and standard-library code for known vulnerabilities.                           |
| `test:unit`        | Run deterministic policy and unit Gherkin cases.                                                         |
| `test:integration` | Exercise local files, leases, evidence, processes, and integration Gherkin cases without network.        |
| `test:e2e`         | Build a temporary public binary, exercise it safely, and remove it on every exit.                        |
| `test:coverage`    | Enforce numeric production coverage at 99% and all three behavior compliance adapters.                   |
| `test:quick`       | Run typecheck, lint, unit, numeric coverage, and all compliance adapters; full integration/E2E stay out. |
| `test`             | Run unit, integration, coverage/compliance, and the full temporary-binary E2E suite serially.            |

System-command adapters and the thin `main` entry are excluded from numeric instrumentation and exercised through integration or compiled-binary E2E boundaries. Production policy remains under the 99% numeric gate.

## Resource policy

Memory admission requires 9 GiB of the macOS non-compressed availability estimate, treats less than 4 GiB as critical, reserves two CPU units, and requires three consecutive safe samples. Release admission reserves six CPU units and at least 13 GiB of deployment disk.

| Signal             | Warning                                      | Critical                                     |
| ------------------ | -------------------------------------------- | -------------------------------------------- |
| Disk free          | Below 30 GiB                                 | Below 20 GiB                                 |
| Swap-out           | At least 128 MiB normalized per 15 seconds   | At least 512 MiB normalized per 15 seconds   |
| Compressor payload | At least 12 GiB and growing 1 GiB per window | At least 16 GiB and growing 2 GiB per window |

Absolute swap use and a stable compressor payload remain evidence only. Evidence schema stays at version 2, session and port markers at version 1, and private bounded evidence defaults to `~/bnest/runtime/resource-guard/`.

## Structure

- `cmd/resource-guard/` is the thin executable entry.
- `internal/cli/` owns argument validation and output.
- `internal/host/` collects macOS metrics.
- `internal/policy/` owns pure development and release decisions.
- `internal/guard/` owns evidence, leases, and child supervision.
- `internal/release/` owns release checks, monitoring, and summary assessment.
- `tests/contract/` owns the shared strict suite configuration, binding registry, and compliance policy.
- `tests/support/` keeps thin Gherkin bindings separate from the scenario driver implementation.
- `tests/unit/`, `tests/integration/`, and `tests/e2e/` contain the three adapters; E2E remains inside this project.
- `tests/coverage/` enforces numeric production coverage.
- `project.json` defines the plugin-free Nx lifecycle.

See [resource-aware development](../../repo-governance/development/resource-aware-development.md) for the canonical agent procedure.
