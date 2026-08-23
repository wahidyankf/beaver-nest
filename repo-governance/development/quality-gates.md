# Quality Gates

Define applicable project gates as Nx targets, invoke them through Nx with the workspace package manager, and document them in the project `README.md`.

## Test Boundaries

- Unit tests replace filesystem, database, process, network, and other system resources with test doubles.
- Integration tests may use real in-process components and isolated local resources, but must never use a network, including loopback or local servers.
- End-to-end tests exercise the public system boundary with production-like resources. Keep their harness in a dedicated Nx app.

## Gate Contracts

| Gate                      | Contract                                                                                                                                                                           |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lint`                    | Reject configured formatting, style, suspicious-code, and dependency-hygiene findings.                                                                                             |
| `typecheck`               | Reject compiler or static-type findings without leaving distributable artifacts.                                                                                                   |
| `test:unit`               | Run fast deterministic tests at the unit boundary. Omit only for a dedicated end-to-end harness.                                                                                   |
| `test:integration`        | Run tests across local real boundaries. Keep it out of `test:quick`.                                                                                                               |
| `test:coverage`           | Compose every applicable named coverage slice. Application line coverage must remain at least 99%.                                                                                 |
| `test:coverage:*`         | Run one documented slice. Narrow exclusions may cover generated, adapter, or non-runtime code when another slice covers it; document the scope in the project README.              |
| `test:coverage:behaviour` | Statically prove every canonical feature, scenario, and step resolves exactly once in every adopted adapter, and every binding is used, without executing slow runtime boundaries. |
| `test:e2e`                | Exercise relevant journeys at the public boundary under the [end-to-end standard](end-to-end-testing.md). Dedicated harnesses must expose this target.                             |
| `test:quick`              | Run `typecheck` → `lint` → `test:unit` → fast coverage slices. Harnesses use `typecheck` → `lint`. Append behavior coverage; never run integration or E2E scenarios.               |
| `pre-commit`              | Run deterministic staged-file checks selected by `lint-staged`.                                                                                                                    |
| `pre-push`                | Run affected `test:quick` gates and repository validation under the [push-hook convention](../conventions/push-hook-verification.md).                                              |

## Application

- Run the narrowest relevant gate during development and keep applicable gates green before completion.
- A deliberate failing test during the red phase of [TDD](test-driven-development.md) is temporary evidence, not a completed state.
- Run `test:quick` after the final red–green–refactor cycle. Select `test:e2e` cases according to the [end-to-end testing standard](end-to-end-testing.md).
- Do not duplicate tool commands outside their canonical Nx target. Aggregate gates must compose named targets. Unsplit projects may use `test:coverage` directly as their single coverage target.
- Layered coverage may scope a fast unit slice to testable core code and a local integration slice to the full application. Each numeric application slice remains at least 99%.
- An end-to-end harness may omit aggregate `test:coverage` when behavior coverage is its only slice.
- Fix failures at their root cause. Do not disable, weaken, bypass, or superficially satisfy a gate to obtain a passing result.
- Do not invent an inapplicable target merely for naming symmetry; explain legitimate omissions in the project README.

This standard follows [minimal sufficiency](../principles/minimal-sufficiency.md), the [project README convention](../conventions/project-readmes.md), and the [TDD standard](test-driven-development.md).
