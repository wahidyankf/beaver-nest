# Behaviour-Driven Development

`badakmini-cli` uses executable Gherkin specifications to make its observable behavior readable and enforceable. This standard applies to that project; it does not require unrelated projects to adopt Gherkin.

## Requirements

- Keep the canonical executable behavior and examples in `.feature` files below `specs/badakmini/cli/behaviours/`.
- Begin new or changed CLI behavior by changing a feature scenario and confirming the expected red result under the repository [TDD standard](test-driven-development.md).
- Discover every `.feature` recursively. Adding or nesting one must not require manual project or runner registration.
- Give every feature exactly one feature-level execution boundary: `@pure` or `@process_global`. Do not place execution-boundary tags below `Feature:`.
- Give every scenario an explicit `When` and `Then`. Reject empty features and undefined or ambiguous steps.
- Keep TickSpec-attributed functions as thin bindings in `BehaviourSteps.fs`; put reusable test operations and state in `BehaviourSupport.fs`.
- Run `@process_global` scenarios serially when they mutate process-wide state. Allow `@pure` scenarios to run in parallel.
- Require 100% line coverage of the thin binding module so implemented phrases cannot remain unused.

## Verification

`test:unit` executes all discovered scenarios. `test:coverage:unit` enforces at least 99% application line coverage, while `test:coverage:behaviour` enforces 100% binding line coverage. `test:coverage` composes both for compatibility, and `test:quick` runs both named targets directly.

Run all commands through Nx from the repository root. The project's [README](../../apps/badakmini-cli/README.md) contains the commands and TickSpec-specific authoring notes.
