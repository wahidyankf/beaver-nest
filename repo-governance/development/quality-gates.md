# Quality Gates

Use the standardized quality gates below for applications and libraries. Define applicable project gates as Nx targets, invoke them through Nx with the workspace package manager, and document them in the project `README.md`.

## Purpose

Quality gates make vibe-coding, AI-assisted development, and rapid iteration sustainable in this repository. They turn shared expectations into progressively broader automated feedback, allowing ideas to move quickly while detecting defects, regressions, and integration risks before they spread. Iteration speed does not lower the quality bar; trustworthy gates are what make that speed safe.

## Gate Contracts

| Gate              | Contract                                                                                                                                                                                                                            |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lint`            | Reject formatting, style, suspicious-code, dependency-hygiene, and other configured static-analysis findings.                                                                                                                       |
| `typecheck`       | Reject compiler or static-type-analysis findings without leaving a distributable build artifact.                                                                                                                                    |
| `test:unit`       | Run fast, deterministic tests at the narrowest practical behavioral boundary. Omit it only where unit tests are not meaningful, such as a dedicated end-to-end harness.                                                             |
| `test:coverage`   | Run the project's coverage gate, composing its named coverage slices when more than one applies. Application line coverage must remain at least 99%.                                                                                |
| `test:coverage:*` | Run one documented coverage slice. Its threshold may be stricter than 99%; exclusions must be narrow, justified by generated or non-runtime code, and documented in the project README.                                             |
| `test:e2e`        | Exercise relevant user or system journeys across their real integration boundaries under the [end-to-end testing standard](end-to-end-testing.md). Dedicated end-to-end projects must expose this target.                           |
| `test:quick`      | Compose the project's fast completion gate in deterministic order. Code projects use `typecheck` → `lint` → `test:unit` → every applicable coverage slice; end-to-end harnesses use `typecheck` → `lint`. Never include `test:e2e`. |
| `pre-commit`      | Run deterministic, staged-file checks selected by `lint-staged`. Keep it fast and scoped to the proposed commit.                                                                                                                    |
| `pre-push`        | Run affected projects' `test:quick` gates and applicable repository validation before remote integration, following the [push-hook verification convention](../conventions/push-hook-verification.md).                              |

## Application

- Run the narrowest relevant gate during development and keep the applicable project gates green before considering the work complete.
- A deliberate failing test during the red phase of [TDD](test-driven-development.md) is temporary evidence, not a completed state.
- Run `test:quick` after the final red–green–refactor cycle. Select `test:e2e` cases according to the [end-to-end testing standard](end-to-end-testing.md).
- Do not duplicate tool commands outside their canonical Nx target. Aggregate gates must compose named targets. Unsplit projects may use `test:coverage` directly as their single coverage target.
- Fix failures at their root cause. Do not disable, weaken, bypass, or superficially satisfy a gate to obtain a passing result.
- Do not invent an inapplicable target merely for naming symmetry; explain legitimate omissions in the project README.

This standard follows [minimal sufficiency](../principles/minimal-sufficiency.md), the [project README convention](../conventions/project-readmes.md), and the [TDD standard](test-driven-development.md).
