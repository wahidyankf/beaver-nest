---
description: >-
  Records which stack packs this repository adopted, the decisions their standards leave open, and every deviation.
when_to_use: >-
  Use when working in a project here, adopting or retiring a stack pack, or changing a recorded stack decision.
---

# Repository Adapter

This document owns the `extensions.software-development` inventory in [`repo-config.yml`](../../../../repo-config.yml).
It follows the [Stack Packs](../../../conventions/structure/stack-packs.md) convention and holds only repository-wide
decisions and deviations; each project's commands and test layers live in its README.

## Adopted Packs

| Pack               | Status  | Reason                                                               |
| ------------------ | ------- | -------------------------------------------------------------------- |
| `elixir`           | adopted | `bnest-app` is Elixir; ExBdd arrives as a tag-pinned git dependency  |
| `phoenix-liveview` | adopted | `bnest-app` is a Phoenix LiveView application                        |
| `javascript`       | adopted | `bnest-app` browser assets and release tools are authored JavaScript |
| `typescript`       | adopted | the asset tests and both end-to-end harnesses are TypeScript         |
| `shell`            | adopted | commit, hook, bootstrap-test, and public-safety scripts              |
| `nx`               | adapted | the workspace keeps no project tags; see the deviation below         |

Every link a copied standard or skill made to a catalog document this repository does not hold was removed, and every
link with a local owner now points at it: [Quality Gates](../../quality-gates.md) stands in for the catalog's test
boundaries, lint strictness, coverage-floor, and task-runner owners.

## Adopter Decisions

Each entry reads **Decision** (Source): Choice — Reason.

- **Stack skills** (`swe-developer`): read on demand (catalog default) — no agent edit when a stack is adopted or
  retired
- **Host-integrated proof** (`swe-developer`): not required (catalog default) — the repository's checks prove behaviour
- **ADR location** (`swe-architect`): `docs/explanation/decisions/NNN-<slug>.md` (default) — beside the existing
  explanations
- **Reviewer output** (`swe-reviewer`): inline — the reviewer stays `read-only`
- **Specification completeness** (`swe-reviewer`): not checked (catalog default) — the Gherkin implementation review
  covers scenarios
- **Test boundary** (`swe-reviewer`): local: [Test Identities](../../test-identities.md) — the repository's own test
  standard
- **Infra target access** (`swe-infra-tester`): named targets, read-only: the routed Caddy service and its blue/green
  slots, through `proxy:status` and health and revision probes — no credential; it never deploys, promotes, or restarts
- **Deploy targets** (`swe-releaser`): `bnest-app` to the routed household service by [Development Caddy
  Deployment](../../../workflows/maintenance/development-caddy-deployment.md), verified by its routed revision — the
  only deployed surface
- **coverage floor** (Meaningful Coverage): 99% line coverage in `test:unit`, as [Quality Gates](../../quality-gates.md)
  sets — stronger local rule, kept; adoption never lowers it
- **end-to-end and shell** (Meaningful Coverage): no numeric coverage — agrees with Quality Gates and the Shell standard
- **task runner** (Quality Gates): Nx targets named in Quality Gates — existing local contract
- **scenario corpus** (`swe-developer`): every project keeps one — stronger local
  [BDD](../../behaviour-driven-development.md) rule, kept
- **lint and success typing** (`elixir-standards.md`): Credo strict and Dialyzer in each project's `lint` and
  `typecheck` — already configured
- **check scope** (`javascript-standards.md`): project-wide `checkJs` — `apps/bnest-app/assets/tsconfig.json` already
  sets it
- **test runner** (`javascript-standards.md`): Vitest — already configured
- **linter** (JavaScript, TypeScript): oxlint — the configured linter; example tools in the standards are illustrative
- **interpreter** (`shell-scripts.md`): Bash with `set -euo pipefail` — catalog default
- **test tool** (`shell-standards.md`): plain Bash test scripts beside the script (`*.test.sh`) — no framework
  dependency
- **report location** (checker and fixer): ignored `generated-reports/`, scratch in `local-tmp/` — root `AGENTS.md`
- **boundary enforcement** ([Hexagonal Architecture](../code/hexagonal-architecture.md)): the `boundary` compiler in
  `bnest-app`, plus its hexagonal layering scan — compile-time and export-aware; it fails the existing `typecheck`

## Skill Names

Adopted `swe-*` agents keep catalog skill names. `cutting-releases` is not adopted: no release is cut here, so
`swe-releaser` lists no skill and follows Development Caddy Deployment.

## Deviations

- **Portable bootstraps.** `./rhino`, `./hippo`, and their bootstrap suites run under POSIX `sh`, so they run on a fresh
  machine before any other shell is known.
- **Nx tags.** No project carries tags, so no Nx module-boundary rule runs and project boundaries are held by review.
  Module boundaries inside `bnest-app` are enforced by the `boundary` compiler under
  [Hexagonal Architecture](../code/hexagonal-architecture.md).
- **Shell formatter.** No formatter gate runs over shell yet, and ShellCheck runs only in the pull-request gate over the
  bootstrap wrappers and their suites.

Closing the last two is separate work; this adoption changed no project configuration.

## Project Applicability

- [bnest-app](../../../../apps/bnest-app/README.md)
- [bnest-app-be-e2e](../../../../apps/bnest-app-be-e2e/README.md)
- [bnest-app-fe-e2e](../../../../apps/bnest-app-fe-e2e/README.md)
- [rhino-consumer](../../../../apps/rhino-consumer/README.md)
- [public-safety](../../../../scripts/public-safety/README.md)
- `repo-scripts` (`scripts/`), `ci-scripts` (`.github/scripts/`), and `claude-hooks` (`.claude/hooks/`) have no README.
  Each holds shell run by a hook or the pull-request gate; behaviour tests, where present, sit beside a script as
  `*.test.sh`, and none carries numeric coverage.

## Version Sources

- `elixir`, `phoenix-liveview`: `apps/bnest-app/mix.exs` and its `mix.lock` file
- `javascript`, `typescript`, `nx`: `package.json` and `package-lock.json`
- `shell`: the interpreter line of each script
