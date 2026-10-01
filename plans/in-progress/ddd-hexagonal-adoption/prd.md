# Product Requirements: DDD and Hexagonal Architecture Adoption

## Personas

- **Maintainer:** the repository owner, who reads diffs, approves the plan, and owns the live service.
- **Coding agent:** `swe-code-maker`, `swe-code-checker` or `swe-code-fixer`. It places code by the standard and is
  stopped by the gate when it gets placement wrong.
- **Household member:** an approved family member using Bnest. This plan must change nothing they can observe.
- **Household operator:** runs the release route, backups and storage operations.

## User Stories

- As a maintainer, I can open one standard and learn where any piece of application code belongs.
- As a coding agent, when I alias `SqliteRepo` from a LiveView or call `File` from a domain module, the gate fails and
  names the offending edge.
- As a coding agent, I can unit-test a facade with in-memory adapters and trust that they behave like the real ones.
- As a household member, every page and journey I use behaves exactly as before, during and after the release.
- As a household operator, I release this revision with the usual managed cutover and the usual rollback.

## Acceptance Criteria

### AC-DH-01: The standard exists and is linked

```gherkin
Scenario: Every reference to the architecture names resolves to the canonical standard
  Given the repository at the closure revision
  When a reader follows "Hexagonal Architecture", "Layers and the Dependency Rule", "Application Shapes",
    "Functional Core, Imperative Shell", "Test Doubles" or "Implementation Stages" from the developing-applications skill,
    the swe-code agents, the programming-elixir skill, and the Elixir, Phoenix LiveView and TypeScript standards
  Then each name is a link to a section of the architecture standard under repo-governance/development/quality/code/
  And rhino-consumer test:repo passes
```

### AC-DH-02: Every application module belongs to a declared boundary

```gherkin
Scenario: No module of bnest-app is unclassified or excepted
  Given the bnest-app sources at the closure revision
  When the project compiles in the test environment with warnings as errors
  Then the boundary compiler reports no unclassified module
  And the @legacy_exports exception list in lib/bnest_app.ex is empty
  And no module other than BnestApp and BnestApp.Mailer is classified to the BnestApp root boundary
```

### AC-DH-03: Crossing a layer fails the gate

```gherkin
Scenario Outline: A forbidden reference fails typecheck
  Given a scratch copy of bnest-app with <caller> referencing <callee>
  When the bnest-app typecheck target runs
  Then it fails with a boundary warning naming <caller> and <callee>

  Examples:
    | caller                             | callee                                       |
    | BnestAppWeb.StorageLive            | BnestApp.SqliteRepo                          |
    | BnestApp.FamilyChat.Domain.Message | Ecto.Adapters.SQL                            |
    | BnestApp.PushNotifications         | BnestApp.FamilyChat.Adapters.SqliteRoomStore |
    | BnestApp.FamilyChat                | BnestApp.FamilyChat.Adapters.SqliteRoomStore |
```

### AC-DH-04: Infrastructure effects live only in adapters

```gherkin
Scenario: The layering scan finds no effect outside an adapter
  Given the sources under apps/bnest-app/lib
  When the hexagonal layering integration test runs
  Then no module outside an Adapters namespace, BnestApp.SqliteRepo, BnestApp.Application, BnestApp.Release,
    BnestAppWeb.Endpoint or BnestAppWeb.Telemetry calls File, Port, System.cmd, System.get_env, :os, :file, Req,
    Ecto.Adapters.SQL, Ecto.Migrator, Ecto.UUID or Exqlite
  And every other module under BnestAppWeb and BnestAppCli is held to the same rule
```

### AC-DH-05: Contexts talk only through facades

```gherkin
Scenario: A cross-context call goes through the published facade
  Given any module in bounded context A that calls bounded context B
  When the boundary compiler checks the call
  Then the callee is B's facade module or a type B exports
  And no inbound adapter calls anything but a facade or an exported domain type
  And no inbound adapter calls BnestApp.Storage.Records, which Storage exports only for other contexts' adapters
```

### AC-DH-06: The unit layer is isolated from infrastructure

```gherkin
Scenario: Unit drivers bind to in-memory adapters
  Given the unit test layer with BNEST_TEST_LAYER=unit
  When test:unit:be runs
  Then no unit driver aliases BnestApp.SqliteRepo or an Adapters module that is not in-memory
  And unit coverage is at least 99 percent of domain and application modules
```

### AC-DH-07: In-memory adapters are proven against real ones

```gherkin
Scenario Outline: One contract suite proves both adapters of a port
  Given the contract suite for <port>
  When it runs at the unit layer against the in-memory adapter
  And it runs at the integration layer against <real adapter>
  Then both runs pass the same scenarios

  Examples:
    | port                                            | real adapter                                                 |
    | BnestApp.FamilyChat.Ports.RoomStore             | BnestApp.FamilyChat.Adapters.SqliteRoomStore                 |
    | BnestApp.Scheduler.Ports.ScheduleStore          | BnestApp.Scheduler.Adapters.SqliteScheduleStore              |
    | BnestApp.PushNotifications.Ports.SubscriptionStore | BnestApp.PushNotifications.Adapters.SqliteSubscriptionStore |
    | BnestApp.Storage.Ports.RecordBackend            | BnestApp.Storage.Adapters.SqliteRecordBackend                |
    | BnestApp.Storage.Ports.RecordBackend            | BnestApp.Storage.Adapters.FileRecordBackend                  |
    | BnestApp.PushNotifications.Ports.DeliveryStore  | BnestApp.PushNotifications.Adapters.SqliteDeliveryStore      |
    | BnestApp.Identity.Ports.IdentityStore           | BnestApp.Identity.Adapters.RecordIdentityStore               |
```

### AC-DH-08: Behaviour is unchanged

```gherkin
Scenario: Every existing behaviour scenario passes unchanged
  Given the specs/apps/bnest Gherkin features at the base revision
  When the closure revision runs test:unit, test:integration and test:coverage:behaviour
  Then no scenario or step text has changed
  And the only feature-file changes are review-invalidated exemption tags listed in learnings
  And every scenario passes at both layers
  And the affected e2e states pass at the exact local origin
```

### AC-DH-09: Persisted state is untouched

```gherkin
Scenario: The release carries no migration and no format change
  Given the closure revision
  When its release manifest is built
  Then its migration set and migrationSetChecksum equal those of the base revision's manifest
  And no file under priv/sqlite_repo/migrations changed
  And no stored record schema version changed
```

### AC-DH-10: Production serves the new architecture without disruption

```gherkin
Scenario: The no-downtime cutover promotes the closure revision
  Given the active route passes proxy status, readiness, 12 exact-origin samples and a representative journey
  When release:run promotes the closure revision of main
  Then routed Caddy HTTP and Tailnet HTTPS report X-Bnest-Revision equal to that revision
  And a synthetic LiveView connects through the routed origin
  And every responsiveness sample from preflight through drain has zero failures, p95 at most 500 ms
    and a maximum of at most 2 seconds
  And no inactive slot or temporary worktree remains
```

## Product Scope

**Changes:** the module structure, the boundaries, the test doubles and contract suites, the governance standard, and the
documentation.

**Unchanged:** every route, LiveView event, GraphQL type and operation, Gherkin scenario, persisted record, table and
configuration value a household member or operator relies on.

## Product Risks

| Risk                                                                          | Signal                                                       | Response                                                                                                                                                    |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A rename breaks a runtime lookup (process name, config key, eval entry point) | Readiness or a release target fails                          | Process names and config keys move in the same unit as their module and are covered by integration readiness tests; `Release.Migrations.*` names are frozen |
| In-memory adapter diverges from SQL semantics                                 | A unit pass hides an integration failure                     | The contract suites of AC-DH-07 run at both layers                                                                                                          |
| A PubSub payload struct is renamed while two slots run                        | A LiveView on the draining slot crashes on an unknown struct | The slots are unclustered, so PubSub is slot-local; the FamilyChat "independent slot-local PubSub" scenario stays green; payload shapes stay the same       |
