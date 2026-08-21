# bnest-app

`bnest-app` is the Phoenix LiveView application that serves Beaver Nest's family-facing web experience. See the [repository README](../../README.md) for the product purpose, shared setup, privacy boundaries, and repository layout.

## Scope

This project owns the OTP application, Phoenix endpoint and router, LiveViews, server-rendered UI, browser assets, and application-level tests. Browser-level acceptance tests belong to [bnest-e2e](../bnest-e2e/README.md).

## Setup and Development

The project requires Elixir `~> 1.17` with Erlang/OTP and Mix. From this directory, install its dependencies and assets once:

```sh
mix setup
```

Run project tasks from the repository root:

| Task                             | Command                                         |
| -------------------------------- | ----------------------------------------------- |
| Start the development server     | `npm exec -- nx run -p bnest-app -t serve`      |
| Run the complete quick suite     | `npm exec -- nx run -p bnest-app -t test:quick` |
| Run ExUnit tests                 | `npm exec -- nx run -p bnest-app -t test:unit`  |
| Run static type analysis         | `npm exec -- nx run -p bnest-app -t typecheck`  |
| Run all linters                  | `npm exec -- nx run -p bnest-app -t lint`       |
| Check Elixir and HEEx formatting | `npm exec -- nx run -p bnest-app -t format`     |

`test:quick` runs `typecheck`, `lint`, and `test:unit` sequentially and stops at the first failure. Type checking treats Elixir compiler warnings as errors, runs Dialyzer through Dialyxir, and strictly checks browser JavaScript without emitting files. Linting checks formatting, runs Credo in strict mode, runs Oxlint on browser JavaScript, and rejects unused locked dependencies without changing the lockfile.

The development server is available at [http://localhost:4000](http://localhost:4000). Normal Elixir, HEEx, JavaScript, and CSS changes reload while it runs. Restart it after dependency, runtime configuration, or supervision-tree changes.

## Structure

- `lib/bnest_app/` contains the OTP application and domain-facing modules.
- `lib/bnest_app_web/` contains the endpoint, router, LiveViews, controllers, and components.
- `assets/` contains browser JavaScript, CSS, and declaration boundaries used for strict checking.
- `config/` contains compile-time and runtime environment configuration.
- `priv/` contains static assets and translations.
- `test/` contains ExUnit support and application tests.

Deployment and production hosting are not implemented yet; follow the [repository plans](../../plans/README.md) rather than treating generated Phoenix deployment comments as the current operating model.
