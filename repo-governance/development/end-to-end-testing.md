# End-to-End Testing

Use end-to-end tests sparingly because they are inherently slower and more expensive than narrower tests. Their purpose is to verify user or system behavior across real integration boundaries, not to recheck behavior that a unit or integration test can prove.

## Development Runs

- Run `test:e2e` only when a change can affect a covered end-to-end journey.
- Select the smallest set of cases that reasonably covers the affected behavior. Pass supported paths, line numbers, or title filters through the canonical Nx target.
- Expand the selection only when shared behavior, broad impact, or unresolved uncertainty makes additional journeys relevant.
- Do not run unrelated cases merely because they are available, and never include `test:e2e` in `test:quick`, pre-commit, or pre-push.

For example:

```sh
npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --grep "A visitor opens Beaver Nest"
```

`bnest-app-e2e` drives the browser from the same recursively discovered Gherkin used by Bnest unit and local-only integration tests. `badakmini-cli-e2e` launches the built CLI as a child process and observes only public commands, exit codes, stdout, stderr, and local filesystem effects. Both keep fast `test:coverage:behaviour` in `test:quick` and runtime E2E outside it.

## Full Suite

The complete suites run in [GitHub Actions](../../.github/workflows/full-e2e.yml) every day at 06:00 and 18:00 in `Asia/Jakarta` (WIB). Each job runs its network-free local integration coverage before its E2E suite. Manual dispatch supports exceptional broad validation or recovery, but routine development must use affected cases.

Keep the scheduled workflow pointed at the canonical `test:e2e` Nx target without case filters. Treat a scheduled failure as a real quality-gate failure: reproduce it, identify the root cause, fix the earliest responsible layer, and rerun the relevant verification without weakening or bypassing the test.
