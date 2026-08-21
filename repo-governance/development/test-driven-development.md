# Test-Driven Development

Develop every new or changed application and library behavior with test-driven development (TDD), using the [red–green–refactor workflow](../workflows/red-green-refactor.md).

## Requirements

- Work in small, observable behavior increments.
- Write or change an automated test before writing the production implementation for each increment.
- Confirm the test fails for the expected behavioral reason before implementing the change; a compilation, configuration, or infrastructure failure does not satisfy the red phase.
- Add only enough production code to make the test pass, then improve the design while keeping the tests green.
- Include bug fixes: first add a test that reproduces the defect, then fix it through the same cycle.
- Keep tests deterministic, focused on behavior, and at the narrowest practical level that gives confidence.
- Run the relevant broader test targets after completing the cycles to detect regressions.

Pure refactoring must begin from a green test baseline, preserve behavior, and keep relevant tests green throughout. If existing code lacks coverage for the behavior being refactored, add characterization tests before restructuring it.

TDD provides executable evidence for intended behavior, catches regressions early, and encourages simpler designs. This standard is subordinate to the repository [vision](../vision/README.md), [principles](../principles/README.md), and [conventions](../conventions/README.md).
