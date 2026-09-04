# Quality Gates

Define applicable project gates as Nx targets, invoke them through Nx with the workspace package manager, and document them in the project `README.md`.

## Test Boundaries

- **Unit** tests run in-process against the subject and replace filesystem, database, environment, clock, randomness, child-process, network, and other OS-facing dependencies with injected doubles. A mocking framework is optional; focused fakes and stubs are valid. Test setup and assertions must not access those real resources.
- **Integration** tests may use real OS resources and same-machine processes, including isolated files, directories, SQLite databases, environment state, child processes, stdin, stdout, and stderr. They must never use a network, including HTTP, TCP, UDP, loopback, `localhost`, `127.0.0.1`, or a locally started server. Isolate and clean every resource deterministically.
- **End-to-end** tests exercise a public system boundary and may use OS resources, processes, and network communication when the journey requires them. Use synthetic identities and isolated data; never touch real users, production data, or uncontrolled external services without explicit authorization.

Classify each test by the strongest real boundary touched by its setup, subject, or assertions. E2E is defined by public-boundary observation, not merely by permission to use more resources. Keep executable tests in separate `unit`, `integration`, and E2E project directories; shared contracts, bindings, fixtures, and non-executable support may remain shared. Put E2E in a dedicated Nx app when a project has a public browser, HTTP, or process boundary. Review topology during changes; do not add a repository-wide topology validator unless a demonstrated risk justifies it.

## Gate Contracts

| Gate                      | Contract                                                                                                                                                                                                              |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lint`                    | Reject configured formatting, style, suspicious-code, and dependency-hygiene findings.                                                                                                                                |
| `typecheck`               | Reject compiler or static-type findings without leaving distributable artifacts.                                                                                                                                      |
| `test:unit`               | Run fast deterministic tests at the unit boundary. Omit only for a dedicated end-to-end harness.                                                                                                                      |
| `test:integration`        | Run tests across local real boundaries. Keep it out of `test:quick`.                                                                                                                                                  |
| `test:coverage`           | Compose every applicable named coverage slice. Numeric line-coverage slices must remain at least 99%.                                                                                                                 |
| `test:coverage:*`         | Run one documented slice. Narrow exclusions may cover generated, adapter, or non-runtime code when another slice covers it; document the scope in the project README.                                                 |
| `test:coverage:behaviour` | Statically prove every canonical feature, scenario, and step resolves exactly once in every adapter required by the [BDD standard](behaviour-driven-development.md), and every binding is used.                       |
| `test:e2e`                | Exercise relevant journeys at the public boundary under the [end-to-end standard](end-to-end-testing.md). Dedicated harnesses must expose this target.                                                                |
| `test:quick`              | Run `typecheck` → `lint` → `test:unit` → fast unit coverage → required static behavior coverage. Dedicated E2E harnesses use `typecheck` → `lint` → static behavior coverage. Never run integration or E2E scenarios. |
| `pre-commit`              | Run deterministic staged-file checks selected by `lint-staged`.                                                                                                                                                       |
| `pre-push`                | Run resource-guarded, sequential affected `test:quick` gates and repository validation under the [push-hook convention](../conventions/push-hook-verification.md).                                                    |

## Application

- Run the narrowest relevant gate during development and keep applicable gates green before completion.
- Invoke compute-bearing local gates through [resource-aware development](resource-aware-development.md); capacity deferral is not a test failure and must not be bypassed.
- A deliberate failing test during the red phase of [TDD](test-driven-development.md) is temporary evidence, not a completed state.
- Run `test:quick` after the final red–green–refactor cycle. Select `test:e2e` cases according to the [end-to-end testing standard](end-to-end-testing.md).
- Do not duplicate tool commands outside their canonical Nx target. Aggregate gates must compose named targets. Unsplit projects may use `test:coverage` directly as their single coverage target.
- Layered coverage may assign documented module ownership to unit and integration slices. Each numeric slice remains at least 99%; when neither slice alone covers the complete denominator, add a combined engine slice so every retained production module remains under the 99% aggregate threshold.
- Runtime and coverage targets for one layer must share setup, isolation, and cleanup prerequisites. Scheduled CI runs every applicable integration coverage target before the owning complete, unfiltered E2E target; integration and E2E remain outside `test:quick` and Git hooks.
- An end-to-end harness may omit aggregate `test:coverage` when behavior coverage is its only slice.
- Fix failures at their root cause. Do not disable, weaken, bypass, or superficially satisfy a gate to obtain a passing result.
- Do not invent an inapplicable target merely for naming symmetry; explain legitimate omissions in the project README.

This standard follows [minimal sufficiency](../principles/minimal-sufficiency.md), the [project README convention](../conventions/project-readmes.md), and the [TDD standard](test-driven-development.md).
