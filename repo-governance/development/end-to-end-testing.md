# End-to-End Testing

Use end-to-end tests sparingly because they are slower and more expensive than narrower tests. They verify behaviour across real integration boundaries, not behaviour a unit or integration test can prove.

Authenticated journeys must follow the [test-identity standard](test-identities.md): `test-user-` usernames, isolated runtime roots and browser profiles, and exact validated cleanup after each run.

Every automated or AI-operated Playwright run must close every page, tab, and browser context it created through guaranteed cleanup that also runs after failure. Before completion, inspect controlled tabs and close test or navigation tabs; retain only a tab explicitly requested as a handoff or deliverable. Never close unrelated user-owned tabs. Cleanup failure fails the run. Formal plans using Playwright must include a `delivery.md` task for this cleanup and its proof.

## Development Runs

- Run `test:e2e` only when a change can affect a covered end-to-end journey.
- Select the smallest set of cases that reasonably covers the affected behaviour. Pass supported paths, line numbers, or title filters through the canonical Nx target.
- Configure the browser base URL with the exact application origin, including hostname and port. A loopback alias such as `127.0.0.1` is not interchangeable with `localhost` when the application validates WebSocket origins; fail on origin or LiveView connection errors instead of accepting HTTP-only success.
- Before filling, clicking, or asserting a LiveView-owned element, wait for its root to reach the connected state. Initial HTTP visibility is not readiness: the first LiveView patch may replace pre-connection form input and make a test submit different data from what it filled.
- Parallel projects or workers may share one marked run root only when each has distinct synthetic identities and user-owned paths. Assertions must observe records owned by the current test identity, never aggregate shared-run counts or paths that another worker can change.
- Expand the selection only when shared behaviour, broad impact, or unresolved uncertainty makes additional journeys relevant.
- Do not run unrelated cases merely because they are available, and never include `test:e2e` in `test:quick`, pre-commit, or pre-push.

## Changed UI Accessibility

For rendered-UI changes, audit affected routes, states, layouts, and themes. Check the accessibility tree, controls, keyboard/focus, non-color cues, narrow reflow, and contrast; run Lighthouse when available. Functional E2E success does not waive a finding.

After automation, manually inspect every affected rendered state in a browser at the exact served origin and each supported viewport class. Exercise the changed interaction and confirm layout, content, focus, and responsive behaviour. Code inspection, inferred CSS behaviour, test results, and design assets are supporting evidence, never substitutes for this rendered check. Record the route, state, viewport class, and pass/fail without private values.

Do not expand this into an unrelated full-site audit. Use synthetic identities and marked cleanup; record only route/state and pass/fail, never private values.

For example:

```sh
npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --project chromium --grep "A visitor opens a fresh chat"
```

The `bnest-app-e2e:test:e2e` target owns its one HIPPO boundary and exclusive port lease, so callers do not wrap it again. It drives the browser from the same recursively discovered Gherkin used by Bnest unit and local-only integration tests. `badakmini-cli-e2e` launches the built CLI as a child process and observes only public commands, exit codes, stdout, stderr, and local filesystem effects. Both keep fast `test:coverage:behaviour` in `test:quick` and runtime E2E outside it.

## Full Suite

The complete suites run in the [scheduled quality-gates workflow](../../.github/workflows/scheduled-quality-gates.yml) every day at 06:00 and 18:00 in `Asia/Jakarta` (WIB). ExBdd runs its complete unit, integration, and engine coverage aggregate; each project with an E2E harness runs network-free integration coverage before its complete E2E suite. Manual dispatch supports exceptional broad validation or recovery, but routine development must use affected cases.

Keep the scheduled workflow pointed at the canonical `test:e2e` Nx target without case filters. Treat a scheduled failure as a real quality-gate failure: reproduce it, identify the root cause, fix the earliest responsible layer, and rerun the relevant verification without weakening or bypassing the test.
