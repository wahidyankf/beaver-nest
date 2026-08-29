# resource-guard

`resource-guard` is the repository bootstrap tool that admits compute-bearing work only when the macOS host has safe memory and CPU headroom. It owns shared host metrics, admission and shedding policy, the heavy-work lease, private evidence, child-process supervision, and the direct CLI.

It does not own Bnest-specific release health, Caddy checks, or service RSS monitoring; those remain in [`apps/bnest-app/tools/resource-monitor.mjs`](../../apps/bnest-app/tools/resource-monitor.mjs). It also does not control production or unrelated processes.

## Bootstrap boundary

Admission must happen before Nx starts the protected workload. Keep the root `npm run resource:status`, `resource:monitor`, and `resource:run` scripts as direct Node entry points. The Nx project owns discovery and development lifecycle targets, but it must not become the only route to the guard.

## Usage and tasks

Run from the repository root. Repository agents additionally retain the required `rtk` prefix.

| Purpose                  | Command                                                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------- |
| Inspect host state       | `npm run resource:status -- --json`                                                                     |
| Monitor state changes    | `npm run resource:monitor`                                                                              |
| Guard an Nx task         | `npm run resource:run -- --class ephemeral -- npm exec -- nx run -p <project> -t <target>`              |
| Check source and format  | `npm run resource:run -- --class ephemeral -- npm exec -- nx run -p resource-guard -t lint`             |
| Run pure unit tests      | `npm run resource:run -- --class ephemeral -- npm exec -- nx run -p resource-guard -t test:unit`        |
| Run process integration  | `npm run resource:run -- --class ephemeral -- npm exec -- nx run -p resource-guard -t test:integration` |
| Enforce all coverage     | `npm run resource:run -- --class ephemeral -- npm exec -- nx run -p resource-guard -t test:coverage`    |
| Run the complete suite   | `npm run resource:run -- --class ephemeral -- npm exec -- nx run -p resource-guard -t test`             |
| Run the fast local suite | `npm run resource:run -- --class ephemeral -- npm exec -- nx run -p resource-guard -t test:quick`       |

The plain ESM sources have no separate type-check target. `lint` performs Node syntax and Prettier checks for the guard plus syntax checks for its direct Bnest and pre-push integration entry points. Pure parser, policy, host-sampling seam, and CLI-orchestration cases run as unit tests; filesystem, lease, signal, and child-process behavior runs as local integration tests. `test:quick` intentionally excludes integration work.

`test:coverage` composes unit and integration coverage slices, each of which fails below 99% line coverage. The unit slice covers `metrics.mjs`, `policy.mjs`, and `cli-application.mjs`. The integration slice covers `evidence.mjs`, `session.mjs`, and `guard.mjs`. The thin `cli.mjs` process adapter is excluded from numeric instrumentation and exercised through a subprocess integration test, matching the repository allowance for adapter exclusions that have a separate boundary test.

## Structure

- `cli.mjs` is the process adapter for `status`, `monitor`, and `run`.
- `cli-application.mjs` owns testable CLI orchestration and validation.
- `metrics.mjs` collects host readings without classifying them as free RAM.
- `policy.mjs` owns development and release headroom decisions.
- `guard.mjs` supervises the admitted child process group.
- `session.mjs` serializes heavy repository work across shells.
- `evidence.mjs` writes bounded private samples and summaries.
- `metrics-policy.test.mjs` covers pure parsing and policy behavior.
- `resource-guard.integration.test.mjs` covers local filesystem and process boundaries.
- `project.json` defines the plugin-free Nx project.

See [resource-aware development](../../repo-governance/development/resource-aware-development.md) for the canonical operating rules and the [root README](../../README.md) for workspace-wide usage.
