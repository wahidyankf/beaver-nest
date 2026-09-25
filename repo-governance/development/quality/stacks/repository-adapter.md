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
| `elixir`           | adopted | `bnest-app` and `libs/ex-bdd` are Elixir                             |
| `phoenix-liveview` | adopted | `bnest-app` is a Phoenix LiveView application                        |
| `javascript`       | adopted | `bnest-app` browser assets and release tools are authored JavaScript |
| `typescript`       | adopted | the asset tests and both end-to-end harnesses are TypeScript         |
| `shell`            | adopted | commit, hook, bootstrap-test, and public-safety scripts              |
| `nx`               | adapted | the workspace keeps no project tags; see the deviation below         |

Every link a copied standard or skill made to a catalog document this repository does not hold was removed, and every
link with a local owner now points at it: [Quality Gates](../../quality-gates.md) stands in for the catalog's test
boundaries, lint strictness, coverage-floor, and task-runner owners.

## Adopter Decisions

| Source                    | Decision                | Choice                                                                            | Reason                                                                 |
| ------------------------- | ----------------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `swe-code-maker`          | stack skill reach       | read on demand                                                                    | no agent edit when a stack is adopted or retired                       |
| Meaningful Coverage       | coverage floor          | 99% line coverage in `test:unit`, as [Quality Gates](../../quality-gates.md) sets | stronger local rule, kept; adoption never lowers it                    |
| Meaningful Coverage       | end-to-end and shell    | no numeric coverage                                                               | agrees with Quality Gates and the Shell standard                       |
| Quality Gates             | task runner             | Nx targets named in Quality Gates                                                 | existing local contract                                                |
| `swe-code-maker`          | scenario corpus         | every project except `libs/ex-bdd` keeps one                                      | stronger local [BDD](../../behaviour-driven-development.md) rule, kept |
| `elixir-standards.md`     | lint and success typing | Credo strict and Dialyzer in each project's `lint` and `typecheck`                | already configured                                                     |
| `javascript-standards.md` | check scope             | project-wide `checkJs`                                                            | `apps/bnest-app/assets/tsconfig.json` already sets it                  |
| `javascript-standards.md` | test runner             | Vitest                                                                            | already configured                                                     |
| JavaScript, TypeScript    | linter                  | oxlint                                                                            | the configured linter; example tools in the standards are illustrative |
| `shell-scripts.md`        | interpreter             | Bash with `set -euo pipefail`                                                     | catalog default                                                        |
| `shell-standards.md`      | test tool               | plain Bash test scripts beside the script (`*.test.sh`)                           | no framework dependency                                                |
| checker and fixer         | report location         | ignored `generated-reports/`, scratch in `local-tmp/`                             | root `AGENTS.md`                                                       |

## Deviations

- **Portable bootstraps.** `./rhino`, `./hippo`, and their bootstrap suites run under POSIX `sh`, so they run on a
  fresh machine before any other shell is known.
- **Nx tags.** No project carries tags, so no module-boundary rule runs; project boundaries are held by review.
- **Shell formatter.** No formatter gate runs over shell yet, and ShellCheck runs only in the pull-request gate over the
  bootstrap wrappers and their suites.

Closing the last two is separate work; this adoption changed no project configuration.

## Project Applicability

- [bnest-app](../../../../apps/bnest-app/README.md)
- [bnest-app-be-e2e](../../../../apps/bnest-app-be-e2e/README.md)
- [bnest-app-fe-e2e](../../../../apps/bnest-app-fe-e2e/README.md)
- [ex-bdd](../../../../libs/ex-bdd/README.md)
- [rhino-consumer](../../../../apps/rhino-consumer/README.md)
- [public-safety](../../../../scripts/public-safety/README.md)
- `repo-scripts` (`scripts/`), `ci-scripts` (`.github/scripts/`), and `claude-hooks` (`.claude/hooks/`) have no README.
  Each holds shell run by a hook or the pull-request gate; behaviour tests, where present, sit beside a script as
  `*.test.sh`, and none carries numeric coverage.

## Version Sources

- `elixir`, `phoenix-liveview`: `apps/bnest-app/mix.exs`, `libs/ex-bdd/mix.exs`, and their `mix.lock` files
- `javascript`, `typescript`, `nx`: `package.json` and `package-lock.json`
- `shell`: the interpreter line of each script
