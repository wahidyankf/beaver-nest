# badakmini-cli-e2e

This Nx app owns process-level end-to-end tests for `badakmini-cli`. It launches the built release DLL with `dotnet`, uses isolated temporary repositories, and observes only public commands, exit codes, stdout, stderr, and filesystem effects.

## Tasks

Run from the repository root through `./resource-guard run --class ephemeral -- <command>` and the workspace [resource guard](../../repo-governance/development/resource-aware-development.md):

| Task                         | Command                                                              |
| ---------------------------- | -------------------------------------------------------------------- |
| Check behaviour completeness | `npm exec -- nx run -p badakmini-cli-e2e -t test:coverage:behaviour` |
| Run process E2E scenarios    | `npm exec -- nx run -p badakmini-cli-e2e -t test:e2e`                |
| Run fast harness checks      | `npm exec -- nx run -p badakmini-cli-e2e -t test:quick`              |
| Type-check the test assembly | `npm exec -- nx run -p badakmini-cli-e2e -t typecheck`               |
| Lint and format-check F#     | `npm exec -- nx run -p badakmini-cli-e2e -t lint`                    |

`test:e2e` builds `badakmini-cli`, checks behaviour completeness across unit, integration, and E2E adapters, then executes every canonical scenario. `test:quick` never launches the CLI process; it owns and sequentially runs type checking, linting, and static behaviour completeness without depending on the CLI application's complete quick gate.

## Shared Specification

The project shares Badakmini's canonical [C4 architecture model](../../specs/apps/badakmini/cli/architecture.md) and recursively embeds the exact corpus below [`specs/apps/badakmini/cli/behaviours/`](../../specs/apps/badakmini/cli/behaviours/). Shared TickSpec bindings and the driver contract come from [`apps/badakmini-cli/tests/contract/`](../badakmini-cli/tests/contract/). The [E2E driver](E2eDriver.fs) translates internal inspection steps into stable `--format json` CLI observations; ordinary command-contract scenarios retain default text output.

The same feature, expanded scenario, and step must execute at unit, local-only integration, and process E2E levels unless that scenario carries the adapter's valid `@integration-exempt` or `@e2e-exempt` tag. Unit has no exemption. `test:coverage:behaviour` proves exact resource parity, one binding per step, no unused bindings, a complete driver, and valid exemption syntax without running runtime scenarios; the [manual implementation review](../../repo-governance/workflows/gherkin-implementation-review.md) separately proves semantic substance.

## Scheduling

The independent **Badakmini test symphony** job in the [scheduled quality-gates workflow](../../.github/workflows/scheduled-quality-gates.yml) runs network-free integration coverage before this process E2E suite at 06:00 and 18:00 WIB. Runtime E2E remains outside `test:quick` and Git hooks.

## Structure

- `Badakmini.Cli.E2eTests.fsproj` embeds shared specifications and links the shared executable `BehaviourTests.fs` test cases into this assembly; the absence of a local `*Tests.fs` file does not mean the suite is empty.
- `E2eDriver.fs` manages temporary repositories and child-process observations.
- `project.json` exposes Nx typecheck, lint, behaviour, quick, and E2E targets.
