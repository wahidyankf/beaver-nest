# bnest-e2e

`bnest-e2e` contains Playwright browser tests for the user-visible behavior of [bnest-app](../bnest-app/README.md). See the [repository README](../../README.md) for shared setup and test commands.

## Scope

This project owns end-to-end scenarios, browser configuration, and assertions across the running application boundary. Component, LiveView, controller, and domain-level tests remain with `bnest-app`.

## Quality Targets

Install the repository dependencies and Playwright's Chromium browser, then run the Nx target from the repository root:

```sh
npm install
npm exec -- playwright install chromium
npm exec -- nx run -p bnest-e2e -t test:quick
```

`test:quick` runs these fail-fast checks in order:

1. `typecheck` checks every `.ts` file with TypeScript strict mode, rejects implicit and explicit `any`, and emits no files.
2. `lint` runs Oxlint's correctness, suspicious, pedantic, and performance rules and rejects explicit `any`.

There is no `test:unit` target because this project owns only end-to-end tests. `test:e2e` is intentionally excluded from `test:quick` because browser tests are slow by nature.

During development, follow the [end-to-end testing standard](../../repo-governance/development/end-to-end-testing.md) and run only cases plausibly affected by the change. Pass a spec path, line number, or `--grep` filter through the Nx target:

```sh
npm exec -- nx run -p bnest-e2e -t test:e2e -- apps/bnest-e2e/tests/greeting.spec.ts
```

The `test:e2e` target uses [playwright.config.mts](playwright.config.mts), starts `bnest-app` at `http://127.0.0.1:4000`, and reuses an already-running local server outside CI. It runs the Chromium project and records a trace on the first retry. The [scheduled GitHub workflow](../../.github/workflows/full-e2e.yml) runs the complete suite at 06:00 and 18:00 WIB.

## Structure

- `playwright.config.mts` defines the browser, base URL, app server, and test directory.
- `tests/` contains user-visible end-to-end scenarios.

Keep tests focused on behavior that requires a real browser or crosses application boundaries. Prefer the narrower `bnest-app:test` target for behavior that does not require Playwright.
