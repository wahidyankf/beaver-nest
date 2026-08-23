# Behaviour-Driven Development

Projects that adopt Gherkin keep observable behavior readable and executable in `.feature` files. This standard currently applies to `badakmini-cli` and `bnest-e2e`; it does not require unrelated projects to adopt Gherkin.

## Shared Requirements

- Keep canonical behavior, inputs, and expected results in the project's `.feature` files below `specs/`.
- Begin new or changed behavior by changing a scenario and confirming the expected red result under the repository [TDD standard](test-driven-development.md).
- Discover every `.feature` recursively. Adding or nesting one must not require manual project or runner registration.
- Give every scenario an explicit `When` and `Then`. Reject empty features and undefined or ambiguous steps.
- Keep bindings thin and put reusable operations or state in support modules.
- Use `test:coverage:behaviour` to reject bindings unused by every feature and prove that every step resolves to exactly one binding without crossing a slow external boundary.

## `badakmini-cli`

- Keep features below `specs/badakmini/cli/behaviours/`.
- Give every feature exactly one feature-level `@pure` or `@process_global` boundary and no scenario-level boundary.
- Keep TickSpec attributes in `BehaviourSteps.fs` and reusable operations in `BehaviourSupport.fs`.
- Run `@process_global` scenarios serially and `@pure` scenarios in parallel.
- Execute every scenario in `test:unit` and realize behavior coverage with 100% binding line coverage in `test:coverage:behaviour`.

## `bnest-e2e`

- Keep English features below `specs/bnest/e2e/behaviours/` and browser bindings in `apps/bnest-e2e/tests/steps/`.
- Make every browser journey originate from Gherkin; reject direct Playwright `.spec` journey files.
- Realize behavior coverage in `test:coverage:behaviour` with fast structure, generation, arity, and binding-completeness checks rather than numeric TypeScript line coverage.
- Include behavior coverage in `test:quick`, but keep browser execution in `test:e2e` under the [E2E standard](end-to-end-testing.md).

Run all commands through Nx from the repository root. Each project README contains its adapter-specific commands and authoring notes.
