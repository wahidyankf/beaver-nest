# Workflows

Workflows define repeatable procedures for repository tasks. A workflow may be complete on its own or compose several smaller workflows when that keeps each procedure focused and reusable.

Workflows are the lowest governance level. Every workflow must conform to the repository [vision](../vision/README.md), [principles](../principles/README.md), [conventions](../conventions/README.md), and [development standards](../development/README.md). When a conflict exists, the workflow must change.

A workflow should define:

- its goal and when to use it;
- prerequisites and required inputs;
- ordered steps;
- verification of the outcome; and
- recovery or rollback guidance when relevant.

When composing workflows:

- link to the canonical workflow instead of copying its steps;
- state the invocation order and any data passed between workflows;
- keep each component usable independently where practical; and
- avoid circular workflow dependencies.

## Directory Map

- [Coding-harness contract change](coding-harness-contract-change.md) keeps canonical rules, skills, agents, capabilities, and native adapters synchronized across supported harnesses.
- [Coding-harness parity verification](coding-harness-parity-verification.md) evaluates repository-owned parity across supported harnesses without changing the contract.
- [Development server restart](development-server-restart.md) restarts an existing local server through its original tmux pane and Nx target.
- [Development Caddy deployment](development-caddy-deployment.md) promotes verified blue/green Phoenix releases behind the stable local Caddy proxy.
- [Development tailnet proxy](development-tailnet-proxy.md) manages a persistent private HTTPS proxy independently from app-server restarts.
- [Exploratory and usability testing](exploratory-and-usability-testing.md) runs the spec-aware exploratory pass and the spec-blind usability pass over a running UI-affecting plan.
- [Gherkin implementation review](gherkin-implementation-review.md) requires an agent to inspect every scenario and adapter for real production behaviour and independent evidence instead of trusting binding counts.
- [Dev artifact clean-up](dev-artifact-clean-up.md) removes the worktree, both copies of the branch, and the build output this work produced, and nothing else, then brings the primary checkout level with `origin/main`.
- [PR leak review](pr-leak-review.md) posts one narrow, current-head review of the diff and is a precondition every merge requires.
- [Plan backlog grooming](plan-backlog-grooming.md) drives every backlog plan to valid, revise, or remove against the repository as it is now.
- [Plan execution check](plan-execution-check.md) judges finished execution in a fixed order and records the verdict archival requires.
- [Plan ideas grooming](plan-ideas-grooming.md) drives every brief in the ideas root to promotion, deliberate retention, or retirement.
- [Plan planning](plan-planning.md) authors a complete formal plan from a request or a groomed brief, bounded by two sequential decision gates.
- [Plan execution](plan-execution.md) moves an explicitly selected plan through active delivery, synchronized task tracking, and dated archival.
- [Plan quality gate](plan-quality-gate.md) runs only on explicit user direction and performs a bounded semantic audit and repair.
- [Red–green–refactor](red-green-refactor.md) defines the repeatable TDD cycle for application and library behaviour.
- [Rules grooming](rules-grooming.md) sweeps the rule corpus for volume carrying no obligation and hands every approved reduction to propagation.
- [Rules propagation](rules-propagation.md) automatically writes every rule change and consumes `NEEDS_PROPAGATION` ledgers without a non-convergence status.
- [Rules quality gate](rules-quality-gate.md) runs only on explicit user direction and cannot end blocked; non-passing findings hand off to propagation.
