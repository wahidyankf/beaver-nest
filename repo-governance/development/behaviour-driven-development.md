# Behaviour-Driven Development

Applications, libraries, executable tools, and repository wrappers express observable behaviour in canonical Gherkin `.feature` files. E2E harnesses implement their application's corpus, never their own. Only `libs/ex-bdd` is exempt.

## Iron Rule

Read relevant features, steps, and tests before production. For observable changes: update Gherkin → bind every adapter → confirm Nx red → implement. Never reorder this. Finish without placeholders; establish a new project's corpus and adapters before its behaviour.

For refactors or implementation-only changes, preserve Gherkin, establish a green baseline or characterization coverage, and keep it green. `libs/ex-bdd` starts from tests under the [TDD standard](test-driven-development.md).

## Required Layers

| Project role                  | Required adapters                                                                                                                                             |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Application                   | Unit, local-only integration, and E2E in a dedicated Nx project; all use the same corpus.                                                                     |
| Library                       | Unit; add local-only integration only when it owns a real local resource boundary. Never add E2E to a library.                                                |
| Executable tool               | Unit; add local integration for owned local resources and E2E for a public process boundary.                                                                  |
| Repository executable wrapper | When no truthful Nx owner exists, one hermetic process adapter invokes the real wrapper and binds its exact corpus through the scheduled repository contract. |
| Dedicated E2E app             | E2E for its owning application's corpus; never an independent behaviour owner.                                                                                |
| `libs/ex-bdd`                 | Exempt.                                                                                                                                                       |

A library without integration owns no local resource boundary. Public-boundary proof belongs to its consumer's E2E corpus. Its README states corpus, adapters, targets, and inapplicable layers.

## Shared Requirements

- Keep executable application corpora in `specs/apps/`, library corpora in `specs/libs/`, and tool or
  repository-wrapper corpora in `specs/tools/`; discover `.feature` files recursively without
  registration.
- Every scenario needs `When` and `Then`; reject empty features and undefined or ambiguous steps. Repeated primary keywords may express one journey; do not split an existing journey merely for uniformity.
- Keep bindings thin and reusable operations or state in support modules.
- Run every feature, expanded scenario, and step in each adapter. Given establishes its precondition, When invokes production through that boundary, and Then independently inspects evidence. No-ops, success literals, expected-result lookups, unrelated assertions, or manufactured asserted values are failing placeholders.
- Unit has no exemption for applications, libraries, and Nx-owned tools. A root wrapper without a truthful Nx owner follows its hermetic-process row. Implement integration and E2E whenever their boundaries can express the scenario. Otherwise add scenario-level `@integration-exempt` or `@e2e-exempt`, each immediately preceded by `# Exemption(<layer>): <boundary reason>; alternative-proof: <Nx test target> / <scenario>`. Reasons identify boundary mismatch, never difficulty, runtime, flakiness, cost, or unfinished work; the alternative proves the concern. Never exempt Feature, Rule, Background, Unit, or all available proof.
- Each project's `test:coverage:behaviour` must prove the exact recursive corpus, complete driver contract, exactly-one step binding, and no unused binding for the adapters it owns. Deleting behaviour requires removing stale bindings.
- Make the corpus an Nx input of its owner and E2E harness. A root repository wrapper with no truthful Nx owner instead keeps its corpus and adapter in the scheduled repository contract. `test:quick` runs unit scenarios and static behaviour coverage, never integration or E2E runtime; follow the [quality-gate](quality-gates.md) and [E2E](end-to-end-testing.md) standards.
- Apply the canonical layer boundaries and folder ownership from the [quality-gate standard](quality-gates.md); boundary setup and assertions count when classifying a test.
- All test support obeys the [test-data iron rule](test-identities.md#iron-rule); exemptions never authorize production access.
- Run the [manual Gherkin implementation review](../workflows/gherkin-implementation-review.md) after adding or materially changing a feature, adapter, exemption, or behaviour-compliance mechanism. Static binding coverage cannot prove semantic implementation.

## Manual Public-Boundary Confirmation

Before completing an observable feature, manually confirm each affected public boundary after automated Gherkin, unit, integration, and E2E coverage. This supplements, never replaces, those layers.

- Use Playwright MCP for affected browser flows against the running application.
- For affected REST, GraphQL, or other HTTP API operations, follow the [API testing standard](api-testing.md); manual `curl` confirmation is mandatory. When browser and API boundaries both change, test both.
- No check is needed when neither boundary is affected; say so in the delivery report.
- In the handoff, record each check's route or command and observed result.

Run application, library, and Nx-owned tool commands through Nx from the repository root. A root
repository wrapper with no truthful Nx owner runs its hermetic process adapter directly through the
scheduled repository contract.
