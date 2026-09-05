# Gherkin Implementation Review

Use this workflow after adding or materially changing a canonical feature, behaviour adapter, exemption, or behaviour-compliance mechanism, and before declaring the affected work complete. Its purpose is semantic review: static binding coverage proves that a binding exists, but cannot prove that the binding implements the behaviour.

## Inputs

- the recursively discovered canonical `.feature` corpus;
- every required Unit, Integration, and E2E adapter;
- the [BDD standard](../development/behaviour-driven-development.md), [test boundaries](../development/quality-gates.md#test-boundaries), [test-data iron rule](../development/test-identities.md#iron-rule), and applicable Nx targets; and
- the changed scope, or the complete corpus when a full audit is requested.

`libs/ex-bdd` owns runner fixtures rather than application behaviour and remains outside this workflow. Its intentionally empty, malformed, undefined, and ambiguous feature fixtures are valid only when a runner test asserts their rejection.

## Review Procedure

Use an agent to perform the review. Do not replace the one-by-one inspection with scenario counts, a grep-only heuristic, or a green test run.

1. Recursively inventory canonical features and expand every Scenario Outline example into its executable scenarios.
2. Create one review row per expanded scenario and required adapter. Record feature, scenario, adapter, binding/support locations, and one of `PASS`, `EXEMPT`, or `FAIL`.
3. For each non-exempt row, trace the whole Given–When–Then path:
   - Given establishes the stated precondition through a boundary-valid fixture or injected double.
   - When invokes the production subject or public boundary named by the scenario.
   - Then reads independent observable evidence produced by that invocation.
   - Fixtures, identities, roots, processes, sessions, and cleanup remain synthetic, isolated, marked, and fail-closed before the subject starts.
4. Mark `FAIL` when any step is empty or a no-op; returns or stores a literal success sentinel; selects success from an expected-outcome table; asserts only generic page text unrelated to the stated behaviour; copies expected data into the value later asserted; simulates a deployment by reconnecting to the unchanged server; or can read, mutate, authenticate against, derive fixtures from, or fall back to production user data. A literal `true` remains a failure when a helper performs an action or embedded assertion first: the value consumed by `Then` must be derived from independently observed evidence.
5. For each exemption, verify the tag is scenario-level, the preceding comment uses the canonical format, the reason is a genuine boundary mismatch, and the named Nx target/scenario provides substantive alternative proof. Review integration and E2E exemptions independently when both annotate one scenario, and verify that unit still proves the behaviour. Unit exemptions always fail; no exemption relaxes test-data isolation. Remove layer-specific no-op or success-sentinel branches for exempt scenarios so accidental execution fails instead of reporting false proof; shared bindings may remain for the implemented adapters.
6. Run the affected Unit, Integration, and E2E behaviour targets. A test failure, `FAIL` row, invalid exemption, missing row, or unresolved `PARTIAL` assessment blocks completion.
7. Store a requested audit as a non-authoritative report under ignored `generated-reports/`. The report must include corpus totals, every review row, findings and fixes, exemption inventory, commands run, and final results.

## Verification

Run the applicable project behaviour targets and the repository governance gate through HIPPO-guarded Nx. Confirm that the report row count equals the expanded scenario count multiplied by its required adapters, minus no rows for exemptions: exempt rows remain explicit and are counted as `EXEMPT`.

Review the final diff for placeholder patterns again after fixes. Static checks may reject known forms, but the agent's semantic inspection remains authoritative for this workflow.

## Recovery

If a row cannot pass, keep it `FAIL` and fix the production seam or adapter. Use one or both higher-layer exemptions only when each omitted layer fundamentally cannot express the scenario and an unexempted named layer proves the omitted concern. Never use an exemption to finish faster, avoid cost, quarantine flakes, or defer implementation.
