# Exploratory and Usability Testing

Required for any [UI-affecting plan](../conventions/plan-ui-design.md) before completion: two independent passes over the running application, kept in separately labeled sections so a reader always knows which lens produced a finding. Drive both passes with Playwright MCP against the running application at its exact served origin, across every supported viewport class. Both are passive and non-destructive under [live-service continuity](../development/live-service-continuity.md) and use isolated [test identities](../development/test-identities.md); neither may mutate shared or production state.

## Prerequisites

Implementation is complete, automated gates are green, and the application is running and reachable at a known exact origin with its supported viewport classes and affected routes identified.

Run the exploratory pass first and finish recording it before the usability pass begins, so the two lenses never blend into one judgment.

## Exploratory Pass

Spec-aware. Compare live behaviour against the affected `specs/**` Gherkin. Actively probe edge cases, boundary conditions, URL/route structure, and passive security signals (exposed identifiers, missing authorization checks) beyond the scripted E2E cases. Record each finding with its route/state and category in `learnings.md` under `## Exploratory findings`.

When a finding reveals correct-but-unspecced behaviour, propose it as a new Gherkin scenario and reconcile it through the [BDD Iron Rule](../development/behaviour-driven-development.md#iron-rule): update the spec, bind failing steps, confirm red, then implement, as its own `delivery.md` task. Never merge an unreconciled proposal into `specs/**` directly.

## Usability Pass

Spec-blind, and blindness must be structural rather than self-declared: a context that implemented the change has already read the specs and cannot un-read them. Delegate this pass to a fresh agent context given only the origin, routes, and viewport classes, and withhold the specs, source, and design assets. When no delegation is available, record that the pass ran spec-aware so its findings are read with that limitation.

Judge only first-time-user perception against Nielsen's ten usability heuristics, a cognitive walkthrough, edge-case UX states (empty, loading, error, zero-result), and responsive usability. Record findings under a separate `## Usability findings` section in `learnings.md`; never merge them with exploratory findings.

When an exploratory and a usability finding describe the same underlying defect, add a short cross-reference note in both sections so the shared root cause is fixed once. A usability-driven spec suggestion follows the same Iron Rule reconciliation as an exploratory spec-gap, labeled separately as usability-sourced.

## Verification

Before the plan's final checkpoint, confirm both passes ran, findings are present (or explicitly recorded as none found) and correctly labeled, cross-references are noted, and every accepted spec proposal completed the Iron Rule with `delivery.md` proof. Record only route/state, category, and pass/fail; never private values.
