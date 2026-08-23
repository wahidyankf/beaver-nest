# Behaviour-Driven Development

Projects that adopt Gherkin keep observable behavior readable and executable in `.feature` files. This standard applies to the Badakmini CLI and Bnest test families; unrelated projects need not adopt Gherkin.

## Shared Requirements

- Keep canonical behavior, inputs, and results in project `.feature` files below `specs/`.
- Begin new or changed behavior by changing a scenario and confirming the expected red result under the repository [TDD standard](test-driven-development.md).
- Discover every `.feature` recursively. Adding or nesting one must not require manual project or runner registration.
- Give every scenario an explicit `When` and `Then`. Reject empty features and undefined or ambiguous steps.
- Keep bindings thin and put reusable operations or state in support modules.
- When multiple levels adopt one specification, execute every feature, expanded scenario, and step at every level. Vary only the adapter boundary.
- Use `test:coverage:behaviour` to prove each adopted adapter embeds the exact recursive corpus, implements the complete driver contract, resolves every step exactly once, and has no unused binding. Keep this check static and fast.

## `badakmini-cli`

- Keep features below `specs/badakmini/cli/behaviours/`.
- Compile one shared TickSpec contract and the exact same feature resources into unit, integration, and `badakmini-cli-e2e` test assemblies. Tags must not select or skip a level.
- Keep unit and integration adapters in distinct folders below `apps/badakmini-cli/tests/`; keep process E2E in the dedicated `apps/badakmini-cli-e2e/` project.
- Apply the [test boundaries](quality-gates.md): unit uses fakes only, integration uses isolated local resources with no network, and E2E invokes the built CLI process through public commands and output.
- Run all canonical scenarios in `test:unit`, `test:integration`, and `test:e2e`. Keep only unit runtime execution and static behavior completeness in `test:quick`.
- Keep TickSpec attributes and reusable steps in the shared contract; adapter-specific mechanics belong in each driver.

## Bnest application

- Keep English features below `specs/bnest/app/behaviours/`, shared Elixir bindings and driver contracts in `apps/bnest-app/test/behaviour/`, distinct app adapters in their unit and integration folders, and browser bindings in `apps/bnest-app-e2e/tests/steps/`.
- Use `ex-bdd` to compile the exact same recursive corpus and shared bindings into both ExUnit layers. Unit uses direct subjects and test doubles for system resources; integration may use real in-process Phoenix components and isolated local resources but must keep the endpoint server disabled and make no network call, including loopback.
- Make every browser journey originate from the same Gherkin corpus; reject direct Playwright `.spec` journey files.
- Run all canonical scenarios in `test:unit`, `test:integration`, and `test:e2e`. Tags must not select or skip a level.
- Make public `test:coverage:behaviour` statically verify all three adapters. Require every feature, expanded scenario, and step at each level, exactly one binding per step, no unused binding, complete driver callbacks, and successful Playwright generation.
- Include unit runtime and behavior coverage in `test:quick`; keep integration runtime and browser execution outside it under the [quality-gate](quality-gates.md) and [E2E](end-to-end-testing.md) standards.

Run commands through Nx from the repository root. Project READMEs contain adapter commands and authoring notes.
