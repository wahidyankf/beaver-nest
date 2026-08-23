# Beaver Nest

Beaver Nest is a private, always-available family application and a focused constituent project of [Open Sharia Enterprise (OSE Public)](https://github.com/wahidyankf/ose-public), the broader initiative for trustworthy, Sharia-compliant products. This separate repository gives Beaver Nest a focused development boundary while keeping its purpose and direction connected to OSE Public. The application uses Phoenix LiveView and Nx for rapid, safe iteration with Codex.

## Status

Beaver Nest is in its first implementation stage.

- A Phoenix LiveView hello-world app, Nx workspace, shared Gherkin unit/integration/E2E tests, and Playwright E2E harness are ready.
- Hot reload works during local development.
- Tailscale Serve, an always-on launch service, authentication, persistent data, backups, and document processing are planned but not yet implemented.

## Run locally

Prerequisites:

- Node.js and npm
- Elixir and Erlang/OTP, including Mix
- .NET 10 SDK
- CMake, when a Phoenix dependency must compile from source

Install dependencies and start the development server:

```sh
npm install
npm start
```

Open [http://localhost:4000](http://localhost:4000).

Phoenix recompiles normal Elixir and HEEx changes while it runs, and its asset watchers update JavaScript and CSS. Restart the server after changing dependencies, runtime configuration, or application startup/supervision setup.

## Test

```sh
npm test
npm exec -- nx run -p bnest-app -t test:integration
npm exec -- nx run -p bnest-app -t test:coverage:behaviour
npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --grep "A visitor opens Beaver Nest"
npm exec -- nx run -p badakmini-cli -t test:integration
npm exec -- nx run -p badakmini-cli-e2e -t test:e2e
```

`npm test` runs the Phoenix unit suite through Nx. Bnest's unit, integration, and browser adapters consume the same recursively discovered feature corpus; `test:coverage:behaviour` statically proves that every adapter implements it completely. Run only affected end-to-end cases during development. Scheduled GitHub Actions jobs run each local integration suite before its complete E2E suite at 06:00 and 18:00 WIB.

## Repository layout

```text
apps/bnest-app/  Phoenix LiveView application
apps/bnest-app-e2e/  Playwright end-to-end tests
apps/badakmini-cli/  F# governance CLI with unit and integration tests
apps/badakmini-cli-e2e/  Process end-to-end tests for the CLI
libs/ex-bdd/  Independently maintained Elixir Gherkin/ExUnit engine
specs/apps/  Canonical application behavior specifications shared across test levels
data/        Ignored local system and user data placeholders
docs/        Diátaxis-organized, non-rule documentation
plans/       Product, architecture, testing, and operations plans
```

## Privacy and availability

The app is intended for private access by family devices on a Tailscale network. The current development endpoint listens only on the local machine; publishing it through Tailscale Serve is planned work.

Never commit user data, documents, database files, credentials, Tailscale auth keys, or backups. The `data/` directory is intentionally ignored except for its directory placeholders.

For the target architecture and operating model, see [the plans index](plans/README.md).

## Development checks

Husky runs lint-staged before each commit. Prettier reformats supported staged files, while staged Phoenix files are checked with `mix format` and the unit test suite. Commitlint requires Conventional Commit messages, for example:

```text
feat(app): add household dashboard
```

Before a push, Husky runs `test:quick` for affected projects. It also runs governance, documentation-map, and Mermaid-accessibility checks when pushed commits change Markdown anywhere or any content under `docs/`. The end-to-end harness keeps browser tests out of `test:quick`; developers run affected browser cases, while GitHub Actions runs the full suite twice daily.

## License

Copyright © 2026 wahidyankf. Beaver Nest is available under the [MIT License](LICENSE).
