# End-to-End Testing

Use end-to-end tests sparingly because they are slower and more expensive than narrower tests. They verify behavior across real integration boundaries, not behavior a unit or integration test can prove.

Authenticated journeys must follow the [test-identity standard](test-identities.md): `test-user-` usernames, isolated runtime roots and browser profiles, and exact validated cleanup after each run.

## Development Runs

- Run `test:e2e` only when a change can affect a covered end-to-end journey.
- Select the smallest set of cases that reasonably covers the affected behavior. Pass supported paths, line numbers, or title filters through the canonical Nx target.
- Configure the browser base URL with the exact application origin, including hostname and port. A loopback alias such as `127.0.0.1` is not interchangeable with `localhost` when the application validates WebSocket origins; fail on origin or LiveView connection errors instead of accepting HTTP-only success.
- Before filling, clicking, or asserting a LiveView-owned element, wait for its root to reach the connected state. Initial HTTP visibility is not readiness: the first LiveView patch may replace pre-connection form input and make a test submit different data from what it filled.
- Parallel projects or workers may share one marked run root only when each has distinct synthetic identities and user-owned paths. Assertions must observe records owned by the current test identity, never aggregate shared-run counts or paths that another worker can change.
- Expand the selection only when shared behavior, broad impact, or unresolved uncertainty makes additional journeys relevant.
- Do not run unrelated cases merely because they are available, and never include `test:e2e` in `test:quick`, pre-commit, or pre-push.

## Changed UI Accessibility

For rendered-UI changes, audit affected routes, states, layouts, and themes. Check the accessibility tree, controls, keyboard/focus, non-color cues, narrow reflow, and contrast; run Lighthouse when available. Functional E2E success does not waive a finding.

Do not expand this into an unrelated full-site audit. Use synthetic identities and marked cleanup; record only route/state and pass/fail, never private values.

For example:

```sh
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --project chromium --grep "A visitor opens a fresh chat"
```

`bnest-app-e2e` drives the browser from the same recursively discovered Gherkin used by Bnest unit and local-only integration tests. `badakmini-cli-e2e` launches the built CLI as a child process and observes only public commands, exit codes, stdout, stderr, and local filesystem effects. Both keep fast `test:coverage:behaviour` in `test:quick` and runtime E2E outside it.

## Full Suite

The complete suites run in [GitHub Actions](../../.github/workflows/full-e2e.yml) every day at 06:00 and 18:00 in `Asia/Jakarta` (WIB). Each job runs its network-free local integration coverage before its E2E suite. Manual dispatch supports exceptional broad validation or recovery, but routine development must use affected cases.

Keep the scheduled workflow pointed at the canonical `test:e2e` Nx target without case filters. Treat a scheduled failure as a real quality-gate failure: reproduce it, identify the root cause, fix the earliest responsible layer, and rerun the relevant verification without weakening or bypassing the test.
