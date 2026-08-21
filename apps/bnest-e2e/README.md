# bnest-e2e

`bnest-e2e` contains Playwright browser tests for the user-visible behavior of [bnest-app](../bnest-app/README.md). See the [repository README](../../README.md) for shared setup and test commands.

## Scope

This project owns end-to-end scenarios, browser configuration, and assertions across the running application boundary. Component, LiveView, controller, and domain-level tests remain with `bnest-app`.

## Run the Tests

Install the repository dependencies and Playwright's Chromium browser, then run the Nx target from the repository root:

```sh
npm install
npm exec -- playwright install chromium
npm exec -- nx run bnest-e2e:e2e
```

The target uses [playwright.config.mjs](playwright.config.mjs), starts `bnest-app` at `http://127.0.0.1:4000`, and reuses an already-running local server outside CI. It runs the Chromium project and records a trace on the first retry.

## Structure

- `playwright.config.mjs` defines the browser, base URL, app server, and test directory.
- `tests/` contains user-visible end-to-end scenarios.

Keep tests focused on behavior that requires a real browser or crosses application boundaries. Prefer the narrower `bnest-app:test` target for behavior that does not require Playwright.
