# Behaviour-Driven Development

Every application, library, and Nx tool below `apps/`, `libs/`, or `tools/` must express observable behaviour in canonical Gherkin `.feature` files. Dedicated E2E harnesses implement their owning application's corpus, not an independent specification. Only the `libs/ex-bdd` runner is exempt.

## Iron Rule

Read relevant features, scenarios, steps, and test code before changing production code. For every observable behaviour change: update Gherkin → bind failing steps in every applicable adapter → confirm Nx red → implement production code. Never skip or reorder this sequence. Finish with no placeholder or unimplemented step; establish a new project's corpus and adapters before its behaviour.

For refactors or implementation-only changes, preserve Gherkin, establish a green baseline or characterization coverage, and keep it green. `libs/ex-bdd` starts from tests under the [TDD standard](test-driven-development.md).

## Required Layers

| Project role      | Required adapters                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------------------- |
| Application       | Unit, local-only integration, and E2E in a dedicated Nx project; all use the same corpus.                      |
| Library           | Unit; add local-only integration only when it owns a real local resource boundary. Never add E2E to a library. |
| Executable tool   | Unit; add local integration for owned local resources and E2E for a public process boundary.                   |
| Dedicated E2E app | E2E for its owning application's corpus; never an independent behaviour owner.                                 |
| `libs/ex-bdd`     | Exempt.                                                                                                        |

A library without integration must own no filesystem, database, process, or similar local boundary. Public-boundary proof belongs to a consuming application's E2E corpus. Its README must state the corpus path, adapters, targets, and any inapplicable integration layer.

## Shared Requirements

- Keep executable application corpora in `specs/apps/` and library corpora in `specs/libs/`; discover `.feature` files recursively without registration.
- Every scenario needs an explicit `When` and `Then`; reject empty features and undefined or ambiguous steps. A scenario may repeat primary keywords to express one continuous user journey; never rewrite an existing journey scenario into single-action scenarios for uniformity alone.
- Keep bindings thin and reusable operations or state in support modules.
- Run every feature, expanded scenario, and step in each applicable adapter. A binding is implemented only when its Given establishes the stated precondition, its When invokes production behaviour through that layer's boundary, and its Then independently inspects resulting evidence. A no-op, literal success, expected-outcome lookup, generic unrelated assertion, or action that manufactures the value asserted by its Then is a placeholder and fails this standard even when binding coverage is green.
- Unit is mandatory and has no exemption. When a scenario fundamentally cannot be exercised at the integration or E2E boundary, add exactly one scenario-level `@integration-exempt` or `@e2e-exempt` tag. Immediately precede the tag with `# Exemption(<layer>): <boundary reason>; alternative-proof: <Nx test target> / <scenario>`. The reason must describe a boundary mismatch, not difficulty, runtime, flakiness, or unfinished work; the named alternative must prove the omitted concern. Never place exemptions on a Feature, Rule, or Background; never combine both exemption tags; never use `@unit-exempt` or `@no-*`; and never exempt all available proof.
- `test:coverage:behaviour` must prove the exact recursive corpus, complete driver contract, exactly-one step binding, and no unused binding. Deleting behaviour requires removing stale bindings.
- Make the corpus an Nx input of its owner and E2E harness. `test:quick` runs unit scenarios and static behaviour coverage, never integration or E2E runtime; follow the [quality-gate](quality-gates.md) and [E2E](end-to-end-testing.md) standards.
- Apply the canonical layer boundaries and folder ownership from the [quality-gate standard](quality-gates.md); boundary setup and assertions count when classifying a test.
- All test support obeys the [test-data iron rule](test-identities.md#iron-rule); exemptions never authorize production access.
- Run the [manual Gherkin implementation review](../workflows/gherkin-implementation-review.md) after adding or materially changing a feature, adapter, exemption, or behaviour-compliance mechanism. Static binding coverage cannot prove semantic implementation.

## Manual Public-Boundary Confirmation

Before completing an observable feature, manually confirm each affected public boundary after automated Gherkin, unit, integration, and E2E coverage. This supplements, never replaces, those layers.

- Use Playwright MCP for affected browser flows against the running application.
- For affected REST, GraphQL, or other HTTP API operations, follow the [API testing standard](api-testing.md); manual `curl` confirmation is mandatory. When browser and API boundaries both change, test both.
- No check is needed when neither boundary is affected; say so in the delivery report.
- In the handoff, record each check's route or command and observed result.

Run commands through Nx from the repository root.
