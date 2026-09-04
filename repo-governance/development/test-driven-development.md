# Test-Driven Development

Develop every new or changed application and library behaviour with test-driven development (TDD), using the [red–green–refactor workflow](../workflows/red-green-refactor.md).

Treat test declarations and implementations as first-class living documentation. Before interpreting or changing production code, read the relevant tests to establish intended behaviour, constraints, and boundaries. For projects governed by [BDD](behaviour-driven-development.md), begin with the canonical Gherkin before reading or changing its test adapters.

## Requirements

- Work in small, observable behaviour increments.
- Write or change an automated test before writing the production implementation for each increment.
- Confirm the test fails for the expected behavioural reason before implementing the change; a compilation, configuration, or infrastructure failure does not satisfy the red phase.
- Add only enough production code to make the test pass, then improve the design while keeping the tests green.
- Include bug fixes: first add a test that reproduces the defect, then fix it through the same cycle.
- Keep tests deterministic, focused on behaviour, and at the narrowest practical level that gives confidence.
- Keep test declarations, support code, and production behaviour synchronized so the tests remain trustworthy documentation.
- Run the relevant broader test targets after completing the cycles to detect regressions.

Pure refactoring must begin from a green test baseline, preserve behaviour, and keep relevant tests green throughout. If existing code lacks coverage for the behaviour being refactored, add characterization tests before restructuring it.

TDD provides executable evidence for intended behaviour, catches regressions early, and encourages simpler designs. This standard is subordinate to the repository [vision](../vision/README.md), [principles](../principles/README.md), and [conventions](../conventions/README.md).
