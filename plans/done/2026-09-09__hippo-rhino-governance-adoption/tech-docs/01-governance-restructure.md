# Governance Restructure

## The Method

Two passes, in this order, per repository.

**Pass one — inventory.** Enumerate every rule in the repository's current `AGENTS.md` as a numbered list before touching anything. HIPPO has sixteen bullets; RHINO has six sections holding roughly thirty. Each numbered item must end the phase with exactly one destination document. An item with no destination stops the phase; it is a rule the restructure was about to drop, and reading the finished tree would never have revealed it.

**Pass two — adoption.** Apply the matrix below. Every source document from this repository gets one of three verdicts, with the reason recorded. Adopted and adapted documents are then merged with the inventory items that belong to them, so the finished tree states each repository's own rules in this repository's structure — not this repository's rules in someone else's tree.

The two passes meet in the same document. `development/specification-maintenance.md` in RHINO, for example, carries the adapted convention _and_ RHINO's own "no unit exemption, and an integration or E2E exemption must name the concrete boundary" rule, which no source document states.

## The Adoption Matrix

Verdicts: **A** adopt largely as written, **A\*** adopt with substantive adaptation, **R** reject.

### Principles

| Source                   | HIPPO | RHINO | Reason                                                                                                                      |
| ------------------------ | :---: | :---: | --------------------------------------------------------------------------------------------------------------------------- |
| `minimal-sufficiency`    |  A\*  |  A\*  | RHINO's "Change Discipline" and HIPPO's reuse rules already say this; the source document gives them a level and a name.    |
| `progressive-disclosure` |   A   |   A   | The justification for both the hierarchy and the word budget. Without it the budget looks arbitrary.                        |
| `governance-continuity`  |   A   |   A   | Rules must survive a harness compacting its context. More relevant here than there: these are the repositories agents edit. |

Each repository additionally authors its own `vision/README.md`. Neither inherits this one — HIPPO's future is a guard nobody notices, RHINO's is a validator that owns no repository's answers, and both already say so in prose that becomes the vision.

### Conventions

| Source                          | HIPPO | RHINO | Reason                                                                                                                                                                               |
| ------------------------------- | :---: | :---: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `rules`                         |   A   |   A   | Defines what a rule is and that each has one canonical source. A hierarchy without it has no interpretation rule for must/should/may.                                                |
| `coding-harness-contract`       |  A\*  |  A\*  | Adapted: no capability server, no Nx MCP, roster and canonical roots per repository.                                                                                                 |
| `commit-authorization`          |   A   |   A   | Both repositories are edited by agents; the permission boundary is identical.                                                                                                        |
| `push-hook-verification`        |  A\*  |  A\*  | Adapted per repository: HIPPO runs its gate unguarded, RHINO keeps its guard. The `--no-verify` rule is unchanged.                                                                   |
| `integration-path`              |  A\*  |  A\*  | The core of this plan. Adapted to each repository's worktree path, gate name, and the absence of a release worktree exception in HIPPO.                                              |
| `thematic-commits`              |   A   |   A   | Both already run commitlint; the convention states what commitlint cannot check.                                                                                                     |
| `pull-request-body`             |   A   |   A   | Both repositories are about to route every change through a pull request, and neither has written down what a body must carry. Unenforced by tooling in its source and here too.     |
| `pull-request-boundaries`       |  A\*  |  A\*  | Adapted at one point: neither is a live service, so "deployable state" becomes releasable state — the resulting `main` must be a commit a release could be cut from.                 |
| `pull-request-merge`            |  A\*  |  A\*  | Adapted to each repository's own aggregate check name. The five preconditions, the draft lifecycle and the no-bypass rule carry unchanged; they authorize an unreviewed merge.       |
| `public-repository-data-safety` |   A   |   A   | Both are public and both `AGENTS.md` files already carry the credential and absolute-path prohibition. This is its proper home.                                                      |
| `directory-maps`                |  A\*  |  A\*  | Adapted: HIPPO maps `specs` and now `repo-governance` but deliberately not `docs`; RHINO maps `docs`, `specs`, and now `repo-governance`.                                            |
| `markdown-links`                |   A   |   A   | Already enforced by the pinned RHINO in HIPPO and by self-validation in RHINO; the rule was never written down.                                                                      |
| `markdown-visualizations`       |  A\*  |  A\*  | Adapted: HIPPO must declare a palette before it can carry its first diagram — today any `classDef` fails against its empty colour lists.                                             |
| `documentation-architecture`    |   A   |   A   | Both `AGENTS.md` files already mandate Diátaxis and a one-section-per-page rule inline. Extracted to its own document.                                                               |
| `language`                      |   A   |   A   | One line, no cost, removes an unstated assumption.                                                                                                                                   |
| `last-resort-questions`         |   A   |   A   | Governs agent behaviour, which is identical across the family.                                                                                                                       |
| `task-tracking`                 |   A   |   A   | Same reason.                                                                                                                                                                         |
| `github-polling`                |   A   |   A   | Newly relevant: both repositories are about to have pull requests whose checks get polled.                                                                                           |
| `project-readmes`               |   R   |   R   | Governs per-project READMEs in a workspace with `apps/` and `libs/`. Both repositories are one project. The "README stays true to the built binary" rule survives in `development/`. |
| `database-audit-columns`        |   R   |   R   | Neither has a database.                                                                                                                                                              |
| `runtime-flat-file-data`        |   R   |   R   | HIPPO writes runtime evidence, but that is product behaviour specified in its `specs/`, not a repository convention.                                                                 |
| `plan-lifecycle`                |   R   |   R   | No `plans/` tree; see non-goals.                                                                                                                                                     |
| `plan-migrations`               |   R   |   R   | Same, and neither migrates data.                                                                                                                                                     |
| `plan-ui-design`                |   R   |   R   | Neither has a user interface.                                                                                                                                                        |
| `plan-specification-changes`    |   R   |   R   | Its kernel — a specification change must land with its implementation — is real and survives in `development/specification-maintenance`.                                             |

### Development

| Source                         | HIPPO | RHINO | Reason                                                                                                                                                                               |
| ------------------------------ | :---: | :---: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `specification-maintenance`    |  A\*  |  A\*  | Both mandate Gherkin-first, strict adapters, and a verified no-op over churn. Adapted to each repository's adapter names and exemption boundaries.                                   |
| `behaviour-driven-development` |  A\*  |  A\*  | Adapted: drop the Elixir binding mechanics; keep the corpus, binding, and no-placeholder rules.                                                                                      |
| `architecture-specifications`  |  A\*  |  A\*  | Both carry `specs/architecture.md` as a C4 model and both require it synchronized with as-built boundaries.                                                                          |
| `test-driven-development`      |   A   |   A   | RED, GREEN, REFACTOR with named evidence. Neither repository states the cycle today.                                                                                                 |
| `dependency-selection`         |   A   |   A   | RHINO's rule — stated need, rejected alternatives, evidence of maintenance, owned consequence — is nearly the source text already.                                                   |
| `quality-gates`                |  A\*  |  A\*  | Heavily adapted. The gate-routing idea survives; every Nx mechanism is removed. Defines quick versus full for `npm run test:quick` / `scripts/test.sh` and `cargo xtask test-quick`. |
| `software-quality-enforcement` |  A\*  |  A\*  | Adapted: drop the REST and GraphQL `curl` obligations. Keep the required-gates rule, the coverage floors, and the no-superficial-satisfaction rule.                                  |
| `end-to-end-testing`           |  A\*  |  A\*  | Adapted hard. Both already define E2E as observing only the process contract; the browser, LiveView, and user-isolation material is dropped entirely.                                |
| `github-actions-storage`       |   A   |   A   | HIPPO already carries the retention, cache-limit, and `$0` budget rule as a bullet. This is its home, and RHINO should hold the same rule.                                           |
| `resource-aware-development`   |  A\*  |  A\*  | RHINO's version is the family rule plus its own guarded hook. HIPPO's version exists to state the exception: HIPPO cannot guard HIPPO, and why that is safe here.                    |
| `test-identities`              |   R   |   R   | No production users and no production data. The kernel — tests use isolated roots — survives inside `quality-gates`.                                                                 |
| `api-testing`                  |   R   |   R   | Neither serves an API. RHINO opens no socket at all, including loopback, by rule.                                                                                                    |
| `live-service-continuity`      |   R   |   R   | Neither is a service.                                                                                                                                                                |

### Workflows

The level the maintainer re-reads, so it is populated rather than nominal.

| Source                                | HIPPO | RHINO | Reason                                                                                                                                                                                                |
| ------------------------------------- | :---: | :---: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _new_ `worktree-to-pull-request`      |   A   |   A   | Authored here. The procedure this plan introduces and therefore the one with no muscle memory behind it: create, install, branch, push, open, wait, merge, delete both.                               |
| _new_ `release-cut`                   |   A   |   A   | Authored per repository from its own rules. HIPPO: `scripts/build-release.sh`. RHINO: `cargo xtask dist` then `cargo xtask checksums`. Both: never replace a tag, never weaken checksum verification. |
| `coding-harness-contract-change`      |   A   |   A   | Changing a canonical skill or agent obliges every adapter in the same change; a procedure is the only way that holds.                                                                                 |
| `coding-harness-parity-verification`  |   A   |   A   | The read-only audit path, distinct from making a change.                                                                                                                                              |
| `gherkin-implementation-review`       |  A\*  |  A\*  | Both repositories forbid placeholder and no-op bindings and neither has a review procedure. Adapted to each adapter naming.                                                                           |
| `red-green-refactor`                  |   A   |   A   | The executable form of the TDD rule.                                                                                                                                                                  |
| `rules-propagation`                   |  A\*  |  A\*  | Adapted: propagates within one repository across its own tree and adapters. It explicitly does not reach across repositories — see drift below.                                                       |
| `rules-quality-gate`                  |   A   |   A   | A restructure this size creates many rules at once; a read-only quality pass over them is worth having.                                                                                               |
| `rules-grooming`                      |   A   |   A   | A restructure this size is exactly what leaves duplicated obligations behind. Adopted with its refusals intact, including that it never raises a word budget and never writes.                        |
| `plan-execution`, `plan-quality-gate` |   R   |   R   | No `plans/` tree.                                                                                                                                                                                     |
| `development-caddy-deployment`        |   R   |   R   | No service, no reverse proxy.                                                                                                                                                                         |
| `development-server-restart`          |   R   |   R   | No long-running server.                                                                                                                                                                               |
| `development-tailnet-proxy`           |   R   |   R   | No tailnet exposure.                                                                                                                                                                                  |
| `exploratory-and-usability-testing`   |   R   |   R   | No interface to explore. A CLI usability pass was considered and declined as scope this plan cannot honestly size.                                                                                    |

### Coverage Tally

Every governance document in the source repository carries a verdict. Nothing was skipped, and nothing was adopted by default.

| Level       | Source documents | Adopted | Rejected |
| ----------- | ---------------: | ------: | -------: |
| Principles  |                3 |       3 |        0 |
| Conventions |               25 |      18 |        7 |
| Development |               13 |      10 |        3 |
| Workflows   |               13 |       7 |        6 |
| **Total**   |           **54** |  **38** |   **16** |

Each repository therefore receives thirty-eight inherited documents plus two authored workflows — `worktree-to-pull-request` and `release-cut` — plus a `README.md` for `repo-governance/` itself and for each of its five levels, plus its own `vision/README.md`. Forty-six files, of which forty state rules.

## Drift Is a Policy, Not an Accident

Each repository's `repo-governance/README.md` states, in its own words, that these documents were extracted from a sibling repository, that no mechanism keeps the three copies synchronized, and that the only shared contract is the machine-checked one: `repo-config.yml` and the RHINO release each repository pins. A future reader finding three different phrasings of the integration path must read that as three repositories having decided, not as one repository having decayed.

`rules-propagation` is adapted to say the same thing from the other direction: it propagates a rule change through the repository it happens in, and stops at that repository's boundary.

## Configuration Changes

### RHINO

- `governance-word-budget`: keep `count: letters-and-digits`. `AGENTS.md` drops from `fail: 1200` to a much smaller index budget; add `repo-governance/**/*.md`. Both numbers are decided during delivery from the finished tree — a budget set before the documents exist is a number, not a policy — and the rule is that a document exceeding it gets split, never that the number gets raised.
- `governance-directory-map.trees`: add `repo-governance` beside `docs` and `specs`.
- `scan.exclude-directories`: add `worktrees` and `local-tmp`. `local-tmp` is a live omission today: it is git-ignored but RHINO walks the filesystem, so scratch Markdown is already reachable by the gate.
- `harness-parity`: replaces the empty roster; see [the harness contract](02-harness-contract.md).

### HIPPO

- `governance-word-budget`: `surfaces` is `[]` today and the declared `count` is therefore inert. It becomes load-bearing, so the counting rule is chosen deliberately rather than inherited — `letters-and-digits` is the stricter reading and matches the sibling, and the change is recorded as a decision because it is one.
- `governance-directory-map.trees`: add `repo-governance` beside `specs`. **Do not add `docs`.** HIPPO excluded it on purpose, with a stated reason: its Diátaxis landing pages link into sections by name, which is a different contract from naming every direct sibling exactly once. Adding it would be exactly the blind adoption this plan exists to avoid.
- `md-mermaid`: the colour lists are empty, which means the first `classDef` anyone writes fails. That was deliberate — the schema forces a repository to decide its palette before it can have one — and the governance hierarchy carries diagrams, so this plan is the moment the decision is due. Okabe-Ito, matching RHINO, because it stays distinguishable under the common colour vision deficiencies; convergence here is a choice, not inheritance.
- `harness-parity`: `**/CLAUDE.md` moves out of `prohibited-instruction-sources` and becomes `canonical.instruction-adapter`. Nested `**/AGENTS.md` and `.claude/rules/**/*.md` join the prohibition list in its place, so the boundary tightens overall rather than loosening.
- `scan.exclude-directories`: add `worktrees`. `.cache`, `node_modules`, `dist`, `coverage`, `local-tmp`, and `generated-reports` are already there.

## What Must Not Change

Coverage floors — HIPPO's 99% deterministic production core, RHINO's 99% over validator modules with two declared exclusions — the exit-code contracts, the release-immutability rules, `#![forbid(unsafe_code)]`, the no-defaults rule, and every exemption boundary carry into the hierarchy with their original force. The restructure moves rules; it does not renegotiate them. Where a budget conflict arises, the document splits.

## Related

- [Technical design](README.md)
- [The harness contract](02-harness-contract.md)
- [Product requirements](../prd.md)
