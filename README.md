# Beaver Nest

Beaver Nest is a private, always-available family application and a focused constituent project of [Open Sharia Enterprise (OSE Public)](https://github.com/wahidyankf/ose-public), the broader initiative for trustworthy, Sharia-compliant products. This separate repository gives Beaver Nest a focused development boundary while keeping its purpose and direction connected to OSE Public. The application uses Phoenix LiveView and Nx for rapid, safe iteration with Codex.

## Status

Beaver Nest is in its first implementation stage.

- A Phoenix LiveView chat streams local Codex responses through the official SDK, discovers the models available to the local Codex installation, and can switch models without discarding the current thread.
- Isolated, non-routed local development can opt into hot reload.
- A persistent Tailscale Serve route reaches a stable loopback Caddy proxy, which promotes immutable Phoenix releases without a manual browser refresh. Bnest now has one-time family-account setup, persistent per-browser login, centralized flat-file chat/learning/theme records, and recoverable browser import.

## Run locally

Prerequisites:

- Node.js and npm
- Codex authentication for the local account (`codex login`)
- Elixir and Erlang/OTP, including Mix
- .NET 10 SDK
- CMake, when a Phoenix dependency must compile from source
- Tailscale, when private HTTPS access from other tailnet devices is required

Install dependencies and start the development server:

```sh
npm install
npm start
```

Open [http://localhost:4020](http://localhost:4020). Development leases `4020`–`4029`; production remains on `4000`/`4001`, browser E2E on `4010`–`4019`, and Caddy on `4100`.

To keep private HTTPS routing available independently from Phoenix, install Caddy once, then expose its stable loopback endpoint through Tailscale without storing the machine-derived URL in the repository:

```sh
BNEST_DEPLOY_ROOT=/machine-local/path npm exec -- nx run -p bnest-app -t proxy:install
npm run tailnet:up
npm run tailnet:status
```

Use `npm exec -- nx run -p bnest-app -t release:run -- --revision <sha>` for a routine deterministic release; do not stop Caddy or reconfigure Tailscale for normal deploys. Caddy stays bound to loopback while accepting the Host header forwarded by Tailscale Serve. Run `npm run tailnet:down` when private HTTPS access should be removed. The first `tailnet:up` may require tailnet approval for HTTPS certificates; see the [Caddy deployment workflow](repo-governance/workflows/development-caddy-deployment.md).

An explicitly isolated `BNEST_STABLE=false` server may recompile normal Elixir and HEEx changes and run asset watchers. The default stable server and configuration, dependency, or supervision changes follow the [development-server restart workflow](repo-governance/workflows/development-server-restart.md).

## Install on a phone or tablet

Open Beaver Nest through its private Tailscale HTTPS address, then use the browser's **Install app** command. In Chrome and other Chromium browsers, this is usually in the browser menu; in Safari on iPhone or iPad, choose **Share → Add to Home Screen**. The installed app opens in its own window and uses the Beaver Nest home-and-nest logo. It caches the application shell for temporary connection loss, but a live Codex chat still needs connectivity to the home host.

The chat starts with `gpt-5.6-terra` at medium reasoning effort in a read-only sandbox. Admins can choose every picker-visible model and supported effort reported by the local Codex installation. Parents are fixed to `gpt-5.6-terra` at medium effort and children to `gpt-5.6-luna` at medium effort; their model and effort controls are not rendered. After one-time setup, approved family members log in with a username and password. Completed conversations—and the prompt, thread ID, and partial transcript of an active turn—are stored in that user's server-owned record and continue across tabs and browsers. After a compatible deployment reconnect, Bnest asks a retained thread to continue an interrupted turn once without repeating shown text. **Clear chat** atomically saves an empty transcript and starts a new thread. If a retained Codex thread cannot resume, Bnest preserves the transcript, reports the fallback, and opens a fresh thread.

## Test

```sh
npm test
npm exec -- nx run -p bnest-app -t test:integration
npm exec -- nx run -p bnest-app -t test:coverage:behaviour
npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --grep "An automatic LiveView reconnect preserves"
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
specs/apps/  Canonical application architecture and behavior specifications
data/        Ignored `prod/` runtime records and mirrored `test/runs/` fixtures
docs/        Diátaxis-organized, non-rule documentation
plans/       Ideas and plans organized by delivery lifecycle
```

## Privacy and availability

The app is intended for private access by family devices on a Tailscale network. The development endpoint remains bound to loopback, and the independently managed Tailscale Serve proxy provides private HTTPS access without exposing Phoenix directly to the LAN or public internet.

Never commit user data, documents, database files, credentials, Tailscale auth keys, or backups. The `data/` directory is intentionally ignored except for its directory placeholders; its layout and write rules follow the [runtime flat-file-data convention](repo-governance/conventions/runtime-flat-file-data.md).

For the current architecture, see the [Bnest C4 specification](specs/apps/bnest/app/architecture.md). Proposed future changes belong in the [plans lifecycle](plans/README.md).

## Development checks

Husky runs lint-staged before each commit. Prettier reformats supported staged files, while staged Phoenix files are checked with `mix format` and the unit test suite. Commitlint requires Conventional Commit messages, for example:

```text
feat(app): add household dashboard
```

Before a push, Husky runs `test:quick` for affected projects. It also runs governance, recursive directory-map checks for documentation, specifications, and plans, plus Mermaid accessibility when pushed commits change Markdown anywhere or relevant mapped content. The end-to-end harness keeps browser tests out of `test:quick`; developers run affected browser cases, while GitHub Actions runs the full suite twice daily.

## License

Copyright © 2026 wahidyankf. Beaver Nest is available under the [MIT License](LICENSE).
