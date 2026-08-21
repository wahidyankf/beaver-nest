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
3. `test:e2e` runs the Playwright browser suite. There is no `test:unit` target because this project owns only end-to-end tests.

Run one check with `npm exec -- nx run -p bnest-e2e -t <target>`. The `test:e2e` target uses [playwright.config.mts](playwright.config.mts), starts `bnest-app` at `http://127.0.0.1:4000`, and reuses an already-running local server outside CI. It runs the Chromium project and records a trace on the first retry.

## Structure

- `playwright.config.mts` defines the browser, base URL, app server, and test directory.
- `tests/` contains user-visible end-to-end scenarios.

Keep tests focused on behavior that requires a real browser or crosses application boundaries. Prefer the narrower `bnest-app:test` target for behavior that does not require Playwright.
