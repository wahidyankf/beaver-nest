# Red–Green–Refactor

Use this workflow for each behaviour increment required by the [test-driven development standard](../development/test-driven-development.md).

## Prerequisites

- Complete the living-documentation review required by the [BDD](../development/behaviour-driven-development.md) and [TDD](../development/test-driven-development.md) standards before inspecting or changing production code.
- Identify the smallest observable behaviour to add or change.
- Identify the narrowest automated test target that can demonstrate it.

## Cycle

```mermaid
flowchart LR
    Red["Red<br/>Expected test failure"] --> Green["Green<br/>Minimum implementation passes"]
    Green --> Refactor["Refactor<br/>Improve design<br/>Keep tests green"]
    Refactor --> Red

    classDef redPhase fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    classDef greenPhase fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    classDef refactorPhase fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    class Red redPhase
    class Green greenPhase
    class Refactor refactorPhase
```

1. **Red:** Write or change one test that expresses the intended behaviour. Run the relevant test target through Nx and confirm it fails because the behaviour is absent or incorrect. Correct the test or environment if it fails for another reason.
2. **Green:** Implement the minimum production change needed for that test. Run the same target and confirm the new test and its surrounding tests pass.
3. **Refactor:** Improve names, structure, duplication, and design without adding behaviour. Keep tests green, running the target after each meaningful refactor.
4. Repeat the cycle for the next behaviour increment.

## Verification

After the final cycle, run the affected project's broader Nx test target and any required repository checks. The completed work must have evidence of the expected red failure and a final green result.

If the test cannot reach red because the test harness or environment is broken, repair or diagnose that problem first. Do not use an unrelated failure as evidence that the behaviour test is valid.
