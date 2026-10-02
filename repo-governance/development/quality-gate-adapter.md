# Quality Gate Adapter

The [Quality Gate Contract](quality-gate-contract.md), [Sole-Writer Propagation](sole-writer-propagation.md), and each family's gate and propagation were copied from the shared catalog. A stronger local rule wins over an adopted one, and every difference is recorded here with its reason.

## Families

| Family      | Subject here                                                     |
| ----------- | ---------------------------------------------------------------- |
| `plan`      | one plan folder under `plans/`                                   |
| `docs`      | every `README.md`, `docs/`, `specs/`, and project documents      |
| `rules`     | `AGENTS.md`, `repo-governance/`, agents, and skills              |
| `harness`   | the Claude Code, Codex, and OpenCode bindings                    |
| `ci`        | `.github/workflows/`, `.husky/`, and the `repo-config.yml` gates |
| `pr-review` | one pull request                                                 |
| `specs`     | listed folders under `specs/`                                    |
| `ui-web`    | `apps/bnest-app`, the Phoenix LiveView interface                 |
| `api-http`  | `apps/bnest-app`, its REST and GraphQL routes                    |

Not adopted: the content, `pdf-to-md`, and tutorial families, because the repository publishes no such content.

## Local Owners

The contract and propagation standards sit flat in this development level, beside the standards they apply, not in a `workflow/` folder. Every adopted link points at the local owner: plans, documentation architecture, directory maps (for indexes and word budgets), the [governance hierarchy](../README.md) (for governance layers), rules, the coding-harness contract (for vendor-neutral governance and harness adapters), decision gates, software quality enforcement, quality gates (for automated quality gates), behaviour-driven development, test identities (for test data isolation), test-driven development, specification maintenance (for the specification tree), GitHub Actions storage, pull-request merge, no destructive Git operations, upstream tool defects, and minimal sufficiency.

A catalog owner with no local counterpart stays named without a link: Bounded Convergence, Finding Criticality and Confidence (the `assessing-criticality-confidence` skill carries its scales), the review disciplines, Web Research Delegation, Deterministic and Judgement Validation, Preexisting Error Resolution, Related Repositories, Temporary Files (`local-tmp/` per `AGENTS.md`), the writing conventions, Release Cut, and the principles this tree does not hold.

## Adopter Decisions

- **Callers.** [Planning](../workflows/plan/plan-planning.md) calls the plan gate after its post-write gate. No workflow calls any other gate: there is no release cut, and rules grooming never invokes the rules gate.
- **Entry and exit check.** The `pre-push` surface in `repo-config.yml`, run as `rhino-consumer:test:repo` under `./hippo`.
- **Structure.** `rhino governance quality-gates validate`, on the pre-push and pull-request surfaces, checks every gate and propagation for its headings, verdicts, retired inputs, and cycle bound against `repo-config.yml`.
- **Deterministic Boundary.** Each gate's last column names the tools this repository runs. No validator checks front matter or plan structure here, so both are judgeable, and plan and specs rows verify by rereading plus the pre-push surface.
- **Review surface.** A hosted pull request, under the [merge preconditions](../conventions/pull-request-merge.md).
- **Review route.** No scout or lens checker is adopted, so every pass takes the trivial tier: `pr-review-checker` reviews the whole change alone and is read-only.
- **Live surface.** The service runs 24/7. A `ui-web` or `api-http` run targets a development server or release candidate with synthetic test identities, and a repair's redeploy is a candidate restart under [live-service continuity](live-service-continuity.md), never the active route.
- **Agent fields.** Catalog `capabilities` become `requires` and `denies`, `read-only` becomes a denied `repository-write` with `inline-result-only`, and `tier` is dropped.
- **Skills not adopted.** `authoring-documentation`, `propagating-rules`, `checking-harness-compatibility`, `applying-ci-standards`, `validating-specification-structure`, `resolving-review-threads`, `developing-frontend-ui`, and the review-synthesis skills. Each executor works from its workflow and agent text, and no agent lists a skill the repository lacks.
- **Docs propagation.** A specification that disagrees with the implementation is asked through `grill-me`, under [last-resort questions](../conventions/last-resort-questions.md).
- **Rules propagation.** Entry becomes automatic through the root instruction file; delivery is the pull request. No parity boundary is declared, so step 9 records no sibling obligation.
- **Harness propagation.** It keeps its earlier automatic trigger, every canonical change, as its [Canonical Change](../workflows/quality/harness-propagation/001-canonical-change.md) module.
- **Plan gate.** The plans convention it audits includes the local [plan lifecycle](../conventions/plan-lifecycle.md), migrations, specification changes, UI design, API testing, and live-service clauses `AGENTS.md` lists.
- **Shape.** Adopted files drop front matter, as every governance document here does.
