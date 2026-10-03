# 004: Test Doubles and Contract Suites

## Today

The behaviour suite runs every Gherkin scenario twice, once per layer, through the `BnestApp.Behaviour.Driver` port
(`test/behaviour/driver.ex`). The step files call only `prepare`, `perform` and `outcome`. Four drivers implement that
port:

| Driver                                                                          | Lines       | Reaches                                                                                                                                                            |
| ------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `test/unit/support/home_page_driver.ex` (`UnitHomePageDriver`, `MemoryBackend`) | about 2,400 | domain modules directly, the in-memory record backend, and `Scheduler.Store`, `Storage.Migration`, `Backup.Run`                                                    |
| `test/unit/support/family_chat_driver.ex` (`UnitFamilyChatDriver`)              | about 2,500 | `FamilyChat.Store`, `Scheduler.Store.*_for_test!`, `SqliteRepo`, `Release.Migrations`, `Backup`, against a real SQLite file under `~/bnest/data/test/family-chat/` |
| `test/integration/support/home_page_driver.ex`                                  | about 2,300 | `Phoenix.LiveViewTest`, `ConnCase`, a real runtime root                                                                                                            |
| `test/integration/support/family_chat_driver.ex`                                | about 2,300 | GraphQL over `ConnCase`, a real SQLite file                                                                                                                        |

The unit layer therefore depends on infrastructure. `MemoryBackend` is the one in-memory adapter that already exists,
and it is the pattern this plan generalizes.

## Target

**Step files and feature files do not change.** Only the drivers and their support change, so AC-DH-08 can be checked
by a diff.

**In-memory adapters**

- Live in `test/unit/support/in_memory/` as `BnestApp.Test.InMemory.<Port>`. Each declares `@behaviour <Port>`.
- Keep state per test, not per node. Every port callback already takes the adapter's handle as its first argument,
  as `DataRepository.Backend` does today (`read(store, kind, owner)`). The facade gets the handle from the
  configured adapter's `new/1`, and a unit test passes its own handle (an `Agent` pid that the case starts with
  `start_supervised!/1`) through the facade's optional `adapters:` keyword. Nothing is looked up from global state, so
  `async: true` stays safe. Facades that run as named processes (`Storage.Records`, `Identity`) take the same
  keyword at `start_link/1`, and unit tests start their own unnamed instance.
- Are selected by `config/test.exs` for the unit layer (`BNEST_TEST_LAYER=unit`) and by the real adapters' defaults for
  the integration layer.
- Implement the port's _semantics_, not its SQL: ordering, idempotency keys, optimistic revision checks, uniqueness, and
  cursor pagination, exactly as the port's `@callback` documentation states them.

**Contract suites**

- Each stateful port's documented semantics are written once as an ExUnit case template in
  `test/support/contracts/<port>_contract.ex` (`BnestApp.Test.Contracts.<Port>Contract`).
- It is used twice:

| Use                                                                                                    | File                                                                | Layer       | Adapter                             |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------- | ----------- | ----------------------------------- |
| `use BnestApp.Test.Contracts.RoomStoreContract, adapter: BnestApp.Test.InMemory.RoomStore`             | `test/unit/bnest_app/family_chat/in_memory_room_store_test.exs`     | unit        | in-memory                           |
| `use BnestApp.Test.Contracts.RoomStoreContract, adapter: BnestApp.FamilyChat.Adapters.SqliteRoomStore` | `test/integration/bnest_app/family_chat/sqlite_room_store_test.exs` | integration | SQLite in an isolated test-run root |

The contract template contains no `File`, `System`, `Port` or network access. It sets state up only through the port
itself, so it passes the unit layer's `BoundaryPolicy` scan when a unit test uses it.

| Port                                        | Contract suite                            | Real adapter proven                                                                                         |
| ------------------------------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `Storage.Ports.RecordBackend`               | `RecordBackendContract`                   | `FileRecordBackend`, `SqliteRecordBackend` (`MemoryBackend` becomes `BnestApp.Test.InMemory.RecordBackend`) |
| `FamilyChat.Ports.RoomStore`                | `RoomStoreContract`                       | `SqliteRoomStore`                                                                                           |
| `Scheduler.Ports.ScheduleStore`             | `ScheduleStoreContract`                   | `SqliteScheduleStore`                                                                                       |
| `PushNotifications.Ports.SubscriptionStore` | `SubscriptionStoreContract`               | `SqliteSubscriptionStore`                                                                                   |
| `PushNotifications.Ports.DeliveryStore`     | `DeliveryStoreContract`                   | `SqliteDeliveryStore`                                                                                       |
| `Preferences.Ports.PreferenceStore`         | none: a thin mapping over `RecordBackend` | `RecordPreferenceStore` (integration test through `ThemeController`)                                        |
| `Identity.Ports.IdentityStore`              | `IdentityStoreContract`                   | `RecordIdentityStore` (over the record backend)                                                             |

Stateless or effect-only ports get a trivial in-memory or recording adapter and no contract suite. Their real adapters
keep their integration tests: `CredentialHasher`, `SessionNotifier`, `PushSender`, `CapacityProbe`, `IgnoreCheck`,
`ArtifactStore`, `DatabaseSnapshot`, `ConfigStore`, `Lock`, `Maintenance`, `AgentSession`, `ModelDiscovery`,
`MessagePublisher`, `ReleaseEnvironment`, `RecordKind`, `TranscriptStore` and `ProgressStore`. The last two are thin
mappings over `RecordBackend`, which already has a contract suite.

## Scenarios Whose Subject Is an Adapter

Some unit-layer scenarios today exercise something that is inherently an adapter: release convergence, the SQLite
backup snapshot, storage migration from flat files to SQLite. After migration:

- the **unit driver** proves the _application decision_ through the facade with in-memory adapters, e.g. "convergence
  is idempotent", "a backup is refused when capacity is insufficient", "migration is refused while the lock is held";
- the **integration driver** keeps proving the _effect_ against a real resource, as it does today.

The scenario text is unchanged. Only what each layer's driver observes changes, which is exactly the division
[test-driven development](../../../../repo-governance/development/test-driven-development.md) asks for. If a
scenario's observable outcome cannot be produced at unit level without the effect, the unit driver reports it through
the in-memory adapter's recorded calls. This is recorded per scenario in `learnings.md` when it happens.

## Test-Only Seams Leave Production Code

`Scheduler.Store.reset_schedule_for_test!/4`, `force_due_for_test!/2`, the other `*_for_test!` functions and
`put_test_schedule/5` are test seams compiled into production modules. In-memory adapters make them unnecessary at unit level. For integration, they move
into `BnestApp.Test.Seeds.Schedules` (`test/integration/support/seeds/schedules.ex`), which seeds SQL directly in the
isolated test root. The fe-e2e scheduled-backup support evaluates it under `MIX_ENV=test`, where
`test/integration/support` is compiled. The production adapters lose them. Each removal is checked at U14 by
`grep -rnE "_for_test|put_test_" apps/bnest-app/lib` returning nothing.

## Layer Guard Extension

`test/behaviour/verify.exs` (`BnestApp.Behaviour.BoundaryPolicy`) gains two unit-layer patterns:

- `BnestApp.SqliteRepo`;
- `\.Adapters\.(?!InMemory)`, which matches any non-in-memory adapter.

The new patterns are added in U3 together with an allow-list of the unit-driver lines that still need them, and each
context unit deletes its lines. U14 requires the allow-list empty, which proves AC-DH-06.
