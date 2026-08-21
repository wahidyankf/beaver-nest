# Minimal Sufficiency

Do the least work that fully satisfies the requested outcome and applicable repository rules. Building software is never free: every line of code creates liability through maintenance, review, testing, security exposure, future changes, and eventual removal. Building is a means, not evidence of progress by itself.

## Requirements

- Start from the explicit need and choose the smallest responsible change that resolves it.
- Prefer a direct configuration, content, or existing-mechanism change over new code, dependencies, abstractions, validators, automation, or infrastructure.
- Add an artifact or mechanism only when it is necessary for the requested outcome, an applicable rule, correctness, safety, or a concrete demonstrated risk.
- Do not convert a one-time change into generalized machinery or speculative enforcement without evidence that the machinery is needed.
- When code is necessary, keep it as small and clear as practical. Every additional line must earn its continuing ownership cost.
- Keep verification proportional to the change and its risk. Stop when the outcome is achieved and all required verification passes.

This principle does not excuse skipping TDD, safety boundaries, required documentation, governance propagation, or other applicable rules; those obligations are part of the necessary work. Among compliant solutions, prefer the one with less lasting complexity and maintenance burden.

This principle is subordinate to the repository [vision](../vision/README.md). Every convention, development standard, and workflow must conform to it.
