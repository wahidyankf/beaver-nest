# bnest-app

`bnest-app` is the Phoenix LiveView application that serves Beaver Nest's family-facing web experience. See the [repository README](../../README.md) for the product purpose, shared setup, privacy boundaries, and repository layout.

## Scope

This project owns the OTP application, Phoenix endpoint and router, LiveViews, server-rendered UI, browser assets, and the unit and local-only integration adapters for Bnest's canonical Gherkin behavior. Browser-level acceptance belongs to [bnest-app-e2e](../bnest-app-e2e/README.md); the reusable Elixir BDD engine belongs to [ex-bdd](../../libs/ex-bdd/README.md).

## Setup and Development

The project requires Elixir `~> 1.18` with Erlang/OTP and Mix. From this directory, install its dependencies and assets once:

```sh
mix setup
```

Run project tasks from the repository root:

| Task                                 | Command                                                        |
| ------------------------------------ | -------------------------------------------------------------- |
| Start the development server         | `npm exec -- nx run -p bnest-app -t serve`                     |
| Run the complete quick suite         | `npm exec -- nx run -p bnest-app -t test:quick`                |
| Run unit scenarios                   | `npm exec -- nx run -p bnest-app -t test:unit`                 |
| Run local-only integration scenarios | `npm exec -- nx run -p bnest-app -t test:integration`          |
| Cover the unit slice                 | `npm exec -- nx run -p bnest-app -t test:coverage:unit`        |
| Cover the integration slice          | `npm exec -- nx run -p bnest-app -t test:coverage:integration` |
| Verify every behavior adapter        | `npm exec -- nx run -p bnest-app -t test:coverage:behaviour`   |
| Run all application coverage slices  | `npm exec -- nx run -p bnest-app -t test:coverage`             |
| Run static type analysis             | `npm exec -- nx run -p bnest-app -t typecheck`                 |
| Run all linters                      | `npm exec -- nx run -p bnest-app -t lint`                      |
| Check Elixir and HEEx formatting     | `npm exec -- nx run -p bnest-app -t format`                    |

`test:quick` runs type checking, linting, unit execution, unit coverage, and static behavior completeness. It intentionally excludes integration runtime and E2E execution. Both numeric coverage slices use Mix line coverage and fail below 99%.

## Shared behavior and boundaries

Every Bnest behavior starts in [`specs/apps/bnest/app/behaviours/`](../../specs/apps/bnest/app/behaviours/). The same recursively discovered feature, expanded scenarios, and shared step bindings run at both application levels:

- The unit adapter calls the subject directly without starting the OTP application. Filesystem, database, process, network, and other system resources must be replaced by test doubles.
- The integration adapter uses real in-process Phoenix components and isolated local resources. The endpoint server remains disabled, and network access—including loopback and local servers—is forbidden.
- The browser adapter lives in `bnest-app-e2e` and exercises the public HTTP boundary.

`test:coverage:behaviour` statically checks the unit, integration, and E2E adapters against the exact corpus. It rejects empty features, scenarios without explicit `When` and `Then`, undefined or ambiguous steps, unused bindings, incomplete drivers, and unit or integration boundary-policy violations.

The unit slice excludes modules owned by integration or generated/static Phoenix code. The integration slice excludes the unit driver and the separately unit-covered JSON error renderer. This keeps each slice focused while requiring both to remain at least 99%.

Type checking treats Elixir compiler warnings as errors, runs Dialyzer through Dialyxir, and strictly checks browser JavaScript without emitting files. Linting checks formatting, runs Credo in strict mode, runs Oxlint on browser JavaScript, and rejects unused locked dependencies without changing the lockfile.

The development server is available at [http://localhost:4000](http://localhost:4000). Normal Elixir, HEEx, JavaScript, and CSS changes reload while it runs. Restart it after dependency, runtime configuration, or supervision-tree changes.

## Structure

- `lib/bnest_app/` contains the OTP application and domain-facing modules.
- `lib/bnest_app_web/` contains the endpoint, router, LiveViews, controllers, and components.
- `assets/` contains browser JavaScript, CSS, and declaration boundaries used for strict checking.
- `config/` contains compile-time and runtime environment configuration.
- `priv/` contains static assets and translations.
- `test/behaviour/` contains the shared driver contract, bindings, adapter hooks, and static completeness check.
- `test/unit/` contains unit tests and the system-resource-free unit driver.
- `test/integration/` contains local-only integration tests and the in-process Phoenix driver.

Deployment and production hosting are not implemented yet; follow the [repository plans](../../plans/README.md) rather than treating generated Phoenix deployment comments as the current operating model.
