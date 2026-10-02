# Quality Workflows

Every quality gate with its propagation, and every single-pass review. Each gate follows the [Quality Gate Contract](../../development/quality-gate-contract.md) and hands its findings to one writer, its family's propagation; the [Quality Gate Adapter](../../development/quality-gate-adapter.md) records how this repository maps them.

## Directory Map

- [API HTTP propagation](api-http-propagation.md) is the `api-http` family's writer: the HTTP service, its tests, and its contract.
- [API HTTP quality gate](api-http-quality-gate.md) judges the running HTTP interface against its contract and behaviour specifications.
- [CI propagation](ci-propagation.md) is the `ci` family's writer: pipeline definitions and hook wiring.
- [CI quality gate](ci-quality-gate.md) judges pipeline definitions and hook wiring against the pipeline standards.
- [Docs propagation](docs-propagation.md) is the `docs` family's writer, run automatically with each change a document describes.
- [Docs quality gate](docs-quality-gate.md) judges documents for stale, obsolete, misplaced, and unreadable content.
- [Exploratory and usability review](exploratory-usability-review.md) runs the spec-aware exploratory pass and the spec-blind usability pass over a running UI-affecting plan.
- [Gherkin implementation review](gherkin-implementation-review.md) requires an agent to inspect every scenario and adapter for real production behaviour and independent evidence instead of trusting binding counts.
- [Harness parity verification](harness-parity-verification.md) evaluates repository-owned parity across supported harnesses without changing the contract.
- [Harness propagation](harness-propagation.md) is the `harness` family's writer, and every canonical change.
- [Harness propagation modules](harness-propagation/README.md) hold the canonical change procedure.
- [Harness quality gate](harness-quality-gate.md) judges the harness bindings for upstream drift.
- [Plan propagation](plan-propagation.md) is the `plan` family's writer, inside one plan folder.
- [Plan quality gate](plan-quality-gate.md) judges a complete plan draft for what structural validation cannot reach.
- [PR leak review](pr-leak-review.md) reviews every outgoing commit privately before each push and posts one narrow, current-head review that every merge requires.
- [PR leak review modules](pr-leak-review/README.md) hold the leak classes, the push review, and the enforcement the entrypoint applies.
- [PR review](pr-review.md) is one semantic review pass of a pinned pull-request head.
- [PR review propagation](pr-review-propagation.md) is the `pr-review` family's writer: it answers every blocking finding.
- [PR review quality gate](pr-review-quality-gate.md) is the iterative review with repairs on one pull request.
- [PR review quality gate modules](pr-review-quality-gate/README.md) hold the review surface, answering findings, and the ceiling.
- [Red–green–refactor](red-green-refactor.md) defines the repeatable TDD cycle for application and library behaviour.
- [Rules propagation](rules-propagation.md) is the `rules` family's writer, run automatically before any rule changes.
- [Rules propagation modules](rules-propagation/README.md) hold statement and conflict, placement, and enforcement.
- [Rules quality gate](rules-quality-gate.md) judges a proposed or effective rule state.
- [Specs propagation](specs-propagation.md) is the `specs` family's writer, inside the listed specification folders.
- [Specs quality gate](specs-quality-gate.md) judges listed specification folders for structure, scenario quality, and alignment.
- [UI web propagation](ui-web-propagation.md) is the `ui-web` family's writer: the web interface, its tests, and its specification.
- [UI web quality gate](ui-web-quality-gate.md) judges the running web interface for behaviour, design fidelity, accessibility, and usability.
