# Beaver Nest

Beaver Nest is a private, always-available family application and a focused constituent project of [Open Sharia Enterprise (OSE Public)](https://github.com/wahidyankf/ose-public), the broader initiative for trustworthy, Sharia-compliant products. This separate repository gives Beaver Nest a focused development boundary while keeping its purpose and direction connected to OSE Public. The application uses Phoenix LiveView and Nx for rapid, safe iteration with Codex.

## Status

Beaver Nest is in its first implementation stage.

- A Phoenix LiveView hello-world app, Nx workspace, ExUnit tests, and Playwright E2E test are ready.
- Hot reload works during local development.
- Tailscale Serve, an always-on launch service, authentication, persistent data, backups, and document processing are planned but not yet implemented.

## Run locally

Prerequisites:

- Node.js and npm
- Elixir and Erlang/OTP, including Mix
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
npm run test:e2e
```

`npm test` runs the Phoenix test suite through Nx. `npm run test:e2e` starts the app temporarily and checks it in Chromium with Playwright.

## Repository layout

```text
apps/bnest-app/  Phoenix LiveView application
apps/bnest-e2e/  Playwright end-to-end tests
data/            Ignored local system and user data placeholders
libs/            Shared workspace libraries
plans/           Product, architecture, testing, and operations plans
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

Before a push, Husky runs the repository-governance and Mermaid-accessibility check only when the pushed commits change a Markdown file anywhere in the repository. Pushes without Markdown changes skip the check.

## License

Copyright © 2026 wahidyankf. Beaver Nest is available under the [MIT License](LICENSE).
