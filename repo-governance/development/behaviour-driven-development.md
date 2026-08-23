# Behaviour-Driven Development

Projects that adopt Gherkin keep observable behavior readable and executable in `.feature` files. This standard currently applies to `badakmini-cli` and `bnest-e2e`; it does not require unrelated projects to adopt Gherkin.

## Shared Requirements

- Keep canonical behavior, inputs, and expected results in the project's `.feature` files below `specs/`.
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

## `bnest-e2e`

- Keep English features below `specs/bnest/e2e/behaviours/` and browser bindings in `apps/bnest-e2e/tests/steps/`.
- Make every browser journey originate from Gherkin; reject direct Playwright `.spec` journey files.
- Realize behavior coverage in `test:coverage:behaviour` with fast structure, generation, arity, and binding-completeness checks rather than numeric TypeScript line coverage.
- Include behavior coverage in `test:quick`, but keep browser execution in `test:e2e` under the [E2E standard](end-to-end-testing.md).

Run all commands through Nx from the repository root. Each project README contains its adapter-specific commands and authoring notes.
