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

| Task                             | Command                               |
| -------------------------------- | ------------------------------------- |
| Start the development server     | `npm exec -- nx run bnest-app:serve`  |
| Run ExUnit tests                 | `npm exec -- nx run bnest-app:test`   |
| Check Elixir and HEEx formatting | `npm exec -- nx run bnest-app:format` |

The development server is available at [http://localhost:4000](http://localhost:4000). Normal Elixir, HEEx, JavaScript, and CSS changes reload while it runs. Restart it after dependency, runtime configuration, or supervision-tree changes.

## Structure

- `lib/bnest_app/` contains the OTP application and domain-facing modules.
- `lib/bnest_app_web/` contains the endpoint, router, LiveViews, controllers, and components.
- `assets/` contains browser JavaScript and CSS.
- `config/` contains compile-time and runtime environment configuration.
- `priv/` contains static assets and translations.
- `test/` contains ExUnit support and application tests.

Deployment and production hosting are not implemented yet; follow the [repository plans](../../plans/README.md) rather than treating generated Phoenix deployment comments as the current operating model.
