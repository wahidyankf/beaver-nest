# DDD and Hexagonal Architecture Adoption

## Status

**In progress.** Requested 2026-10-01 by the repository owner, who asked for this plan to be written directly under
`plans/in-progress/` and executed through to production. All six documents exist. Both planning decision gates have
run, and their records are in [`learnings.md`](learnings.md) (D1–D17). The plan quality-gate verdict is recorded there
too. [`delivery.md`](delivery.md) is the only progress record.

## Outcome

Every line of Bnest application code sits in a named layer of a named bounded context, and the compiler refuses code
that crosses a layer or a context the wrong way.

- A **bounded context** (Identity, Preferences, FamilyChat, PushNotifications, Scheduler, Backup, CodexChat, SifatAllah, Storage,
  Operations) owns its ubiquitous language and publishes one **facade**: its application layer.
- Inside a context, the **domain** is pure, **ports** are Elixir behaviours, and **adapters** are the only code that
  touches SQLite, the filesystem, the network, OS processes, or another framework.
- Phoenix, LiveView, Absinthe, Mix tasks and release entry points are **inbound adapters**. They call facades and
  nothing else.
- The [`boundary`](https://boundary.hexdocs.pm/Boundary.html) compiler turns every violation into a warning, and the
  existing `typecheck` target already compiles with `--warnings-as-errors`.
- A repository standard defines all of this. The skill, the agents and the stack standards that already cite
  "Hexagonal Architecture" by name finally link to something.

The household sees no change. Every page, every GraphQL operation, every persisted record and every SQLite table
behaves exactly as before. The release is an ordinary no-downtime Caddy cutover. Its release manifest
carries the same migration set and `migrationSetChecksum` as the base revision's, and no migration file changes.

## Context

The adopted language-neutral skill
[`developing-applications`](../../../.agents/skills/developing-applications/SKILL.md), the
`swe-code-maker`/`checker`/`fixer` agents, and the Elixir, Phoenix LiveView and TypeScript stack standards already place
code by "Hexagonal Architecture", "Functional Core, Imperative Shell", "Layers and the Dependency Rule", "Application
Shapes" and "Test Doubles". None of those documents exists in this repository. When the catalog was adopted, the links
were removed and only the names remained
([`repository-adapter.md`](../../../repo-governance/development/quality/stacks/repository-adapter.md)).
No module-boundary rule runs anywhere; that file records that "project boundaries are held by review".

The one application, `apps/bnest-app` (about 15k lines of Elixir under `lib/`), shows what review alone produced:

- `FamilyChat.Store`, `Scheduler.Store`, `PushNotifications` and `PushNotifications.Dispatcher` call
  `SqliteRepo.query!` directly, and `PushNotifications` reaches into `FamilyChat.Store`, bypassing the FamilyChat
  facade.
- `Backup` shells out to `df` and `git` from the same modules that hold its retention rules.
- `StorageLive` runs Ecto migrations, raw SQL and `File.*` from a LiveView. `HealthController` queries `SqliteRepo`.
  `ChatLive` chooses its own Codex adapter and orchestrates the use case. `SifatAllahLive`,
  `AdminScheduleSettingsLive`, `DataMigrationLive`, `ThemeController` and `UserAuth` call stores directly.
- `DataRepository.Schema` and `Normalizer` depend on the `Chat` and `SifatAllah` domain modules, so a piece of storage
  infrastructure depends on the domains that store records through it.
- The "unit" behaviour drivers write real SQLite files, so the unit layer is not isolated from infrastructure.

Three ports already exist and are kept: `DataRepository.Backend`, `Codex.Session` and `Codex.ModelDiscovery`.

## Scope Boundary

**Included.**
- The governance standard and its propagation: skill, agents, stack standards, enforcement map, `AGENTS.md`, docs.
- The `boundary` dependency and boundary declarations for every module under `apps/bnest-app/lib`.
- The restructure of all ten bounded contexts into facade, domain, ports and adapters.
- Thin inbound adapters (web, GraphQL, Mix, release).
- In-memory adapters with shared contract suites, so the unit layer stops touching infrastructure.
- A source-scan layering test.
- The C4 component update, project README updates, a production release, and archival.

**Excluded.**
- Any behaviour change, Gherkin outcome change, GraphQL schema change, SQLite schema migration, or persisted-record
  format change.
- Event sourcing, CQRS, domain events beyond the existing PubSub broadcasts, and Ecto schemas or changesets for the
  raw-SQL stores.
- The frontend JavaScript, which already isolates `transport`, `persistence` and `store` behind injectable contracts.
- `libs/ex-bdd`. The e2e projects change only where their test support evaluates a module this plan renames
  (listed per unit in [006](tech-docs/006-file-impact.md)); their features, steps and journeys do not.

## Locked Decisions

| Decision | Selected contract |
| --- | --- |
| Scope | All ten bounded contexts migrated before the production release |
| Enforcement | `boundary` compiler; violations are warnings, and `typecheck` compiles with `--warnings-as-errors` |
| Layering depth | Strict context boundaries containing `Domain`, `Ports` and `Adapters` sub-boundaries; the facade is the application layer |
| Unit-layer doubles | Hand-written in-memory adapters, each proven against the real adapter by one shared contract suite |
| Pull requests | One per coherent delivery unit, landed serially: plan → standard → tooling → one per context → closure |
| Naming | `Chat` + `Codex.*` become `CodexChat`; `DataRepository` + `Storage.*` become one `Storage` context; `Deployment` + `AdminConfig` become `Operations`; theme preference becomes its own `Preferences` context; `Release.Migrations.*` keep their names |
| Behaviour | Structural refactor only; no Gherkin outcome, schema or record-format change; release migration set and checksum unchanged from the base revision |
| Mocks | No Mox or Hammox; no new test dependency |

The reasoning and rejected alternatives for each are in [`learnings.md`](learnings.md).

## Approach

The [standard](tech-docs/001-architecture-standard.md) comes first, so every later unit has a rule to point at. Next
come the [tooling](tech-docs/003-boundary-enforcement.md) and a single temporary exception list that names every module
not yet migrated. The [context map](tech-docs/002-target-architecture-and-context-map.md) is then delivered one bounded
context at a time, foundations first (each consumer then migrates onto its provider's final facade), and each context
removes its modules from the exception list as it lands. The
closure unit proves the list is empty and that the layering test, every gate, and the affected end-to-end states pass.
Only then is `main` released through the managed Caddy cutover.

Each refactor follows the repository's test-first cycle in this order:

1. **RED.** Declare the context's strict boundaries and remove it from the exception list. `typecheck` fails, naming
   each violation; the new layering scan fails too.
2. **GREEN.** Move the code into its layers until both pass.
3. **REFACTOR.** Clean up while green, with the unchanged Gherkin suite proving behaviour at both layers.

## Delivery Units

| Unit | Pull request purpose | Lands when |
| --- | --- | --- |
| U1 | This plan | Plan quality gate terminal and non-blocking |
| U2 | Architecture standard and its propagation | `rhino-consumer:test:repo` green |
| U3 | `boundary` tooling, root boundaries, exception list, layering test, test-support classification | All bnest-app gates green with every context excepted |
| U4–U13 | One bounded context each, foundations first: Storage, Identity, Preferences, SifatAllah, CodexChat, FamilyChat, PushNotifications, Scheduler, Backup, Operations | That context's modules have left the legacy root boundary and all gates are green |
| U14 | Closure: empty exception list, C4, READMEs, e2e proof | Every acceptance criterion except the release ones is met |
| U15 | Archival, after the production release | Execution check verdict permits it |

**Work location:** the worktree `worktrees/ddd-hexa`, reused for every unit. Each unit gets a fresh branch from the
synced `origin/main` after the previous unit lands. The release is the one step run from the primary checkout.

## Dependencies and Authority

- **New dependency:** `boundary` (hex `~> 0.11`, MIT, no transitive dependencies, compile-time only), justified under
  [dependency selection](../../../repo-governance/development/dependency-selection.md) in
  [tech-doc 003](tech-docs/003-boundary-enforcement.md).
- **Release:** governed by [live-service continuity](../../../repo-governance/development/live-service-continuity.md)
  and the [Caddy deployment workflow](../../../repo-governance/workflows/development-caddy-deployment.md). See
  [tech-doc 005](tech-docs/005-release-continuity-and-rollback.md).
- **Backlog interaction:** [`family-learning-engine`](../../backlog/family-learning-engine/README.md) plans new
  `BnestApp.Learning` and `EventLog` modules and edits `sifat_allah_live.ex` and `application.ex` against today's
  layout. This plan restructures both, and does not edit that plan; the conflict is reported to the owner at
  completion.
- **Authority:** the repository owner authorized committing, pushing, opening pull requests, merging under the
  [merge preconditions](../../../repo-governance/conventions/pull-request-merge.md), the production release, archival
  and [dev artifact clean-up](../../../repo-governance/workflows/dev-artifact-clean-up.md), all in one goal stated on
  2026-10-01.

## Directory Map

- [`brd.md`](brd.md): the business goal, the roles served, the outcomes, the non-goals and the business risks.
- [`delivery.md`](delivery.md): the ordered checklist, with its TDD cycles, release, recovery and archival steps.
- [`learnings.md`](learnings.md): the decision records and the execution log.
- [`prd.md`](prd.md): the personas, user stories, acceptance criteria, product scope and product risks.
- [`tech-docs/`](tech-docs/README.md): the seven ordered technical documents.
