# 003: Boundary Enforcement

## Dependency Decision: `boundary`

Recorded under [dependency selection](../../../../repo-governance/development/dependency-selection.md).

- **Requirement.** Fail the existing gate when a module calls into a context's internals, an inner layer calls an outer
  one, or a non-adapter calls an infrastructure library. The check must cover every call the compiler sees, not a
  sample.
- **Built-in alternatives considered.**
  - `mix xref graph` emits file-level edges but has no notion of boundaries, exports or layers. An in-repo checker over
    its output would reimplement `boundary`'s classifier, export model and external-app checks, and could only run after
    compilation as a separate step.
  - A regex source scan sees text, not calls. Aliases, imports and `defdelegate` defeat it.
  - Credo has no cross-module dependency analysis.

  The source scan is still kept, for the one thing `boundary` cannot see: calls into the standard library (`File`,
  `System`, `Port`, `:os`), which are not a separate application.

- **Selection evidence (2026-10-01).**
  - hex `boundary` 0.11.0, released 2026-09-17 (0.10.4 shipped 2024-09-25).
  - MIT licence, about 329k recent downloads.
  - Maintained by Saša Jurić at `github.com/sasa1977/boundary`, with a public issue tracker and changelog.
  - No runtime or transitive dependencies; requires Elixir `~> 1.10` (the repository uses `~> 1.18`).
  - The de facto Elixir library for compile-time boundary enforcement, as its download volume indicates.
- **Ownership impact.** Compile-time only (`runtime: false`), so nothing ships in the release. Removing it means
  deleting the `use Boundary` lines and the compiler entry. The version is locked in `mix.lock`, and the existing
  `deps.unlock --check-unused` and dependency review gates cover it.

```elixir
# apps/bnest-app/mix.exs
compilers: [:boundary, :phoenix_live_view] ++ Mix.compilers(),
boundary: [default: [check: [apps: [:ecto, :ecto_sql, :exqlite, :req, :web_push, :argon2_elixir]]]],
{:boundary, "~> 0.11", runtime: false}
```

The `default: [check: [apps: …]]` setting makes those infrastructure applications behave as boundaries for every
module. Only boundaries that list them in `deps` (the adapters and `SqliteRepo`) may call them, so the facade and the
domain are refused even when their own boundary is relaxed.

## Where Violations Surface

Boundary violations are compiler warnings. The `typecheck` target already runs
`MIX_ENV=test mix compile --warnings-as-errors --force`, so a violation fails `typecheck`, `test:quick`, the pre-push
hook and the `Quality gate` pull-request check without any change to `project.json`. Development compiles (`serve`)
show the same warnings without failing, which matches how every other compiler warning behaves.

## The Legacy Exception List

The migration lands one context per pull request, so `main` must stay green while some contexts are not yet migrated.
Unmigrated modules sit in the relaxed `BnestApp` root boundary, where they can call each other and `SqliteRepo`
exactly as today. Callers outside the root can reach them only if the root exports them:

```elixir
# apps/bnest-app/lib/bnest_app.ex
@legacy_exports [
  # Temporary. Every entry is a module not yet moved into a strict context boundary.
  # Delete entries as each context lands; the closure unit (U14) requires this list empty.
  BnestApp.DataRepository,
  …
]
use Boundary, deps: [BnestApp.SqliteRepo], exports: @legacy_exports
```

- U3 seeds `@legacy_exports` with exactly the modules that `BnestAppWeb`, `BnestAppCli`, `BnestApp.Application` and
  `BnestApp.Release` call today, discovered by compiling with an empty list and reading the warnings.
- A migrated context's facade never lists `BnestApp`. When the context still needs a legacy module, a port's adapter
  makes the call, and the context's `Adapters` boundary lists `BnestApp` until the callee migrates. `BnestAppWeb`,
  `BnestAppCli`, `BnestApp.Release` and `BnestApp.Application` list `BnestApp` the same way, and also list each
  migrated context facade they call.
- The root's own `deps` grow and shrink with the migration. When a unit migrates a context that legacy modules still
  call, it adds that facade to the root's `deps`; the unit that migrates the last such caller removes it. `boundary`
  rejects dependency cycles, and none can form: the root lists only `SqliteRepo` and facades; a facade lists only
  other facades and external apps; and no boundary on those paths lists `BnestApp`, `BnestAppWeb`, `BnestAppCli`,
  `BnestApp.Release`, `BnestApp.Application` or an `Adapters` boundary, so no path leads back to the root.
- The list only ever shrinks. A unit that adds an entry fails its checkpoint.
- Three inbound adapters call infrastructure directly today, which no root export can cover, because
  `BnestApp.SqliteRepo` is its own boundary and infrastructure applications are implicit external boundaries. U3
  therefore declares these temporary `deps`, each marked `# legacy: removed in Uxx`, and the named unit deletes it:

  | Boundary      | Temporary deps                                              | Caller today               | Removed in    |
  | ------------- | ----------------------------------------------------------- | -------------------------- | ------------- |
  | `BnestAppWeb` | `BnestApp.SqliteRepo`, `Ecto.Migrator`, `Ecto.Adapters.SQL` | `StorageLive`              | U4 (`Ecto.*`) |
  | `BnestAppWeb` | `BnestApp.SqliteRepo`                                       | `HealthController`         | U13           |
  | `BnestAppCli` | `BnestApp.SqliteRepo`, `Ecto.Migrator`                      | `bnest.storage.migrate`    | U4            |
  | `BnestAppCli` | `Argon2`                                                    | `bnest.identity.benchmark` | U5            |

  `BnestApp.SqliteRepo` stays in `BnestAppWeb`'s deps until U13, so the `StorageLive` → `SqliteRepo` forbidden-edge
  proof (AC-DH-03 row 1) runs at U14, once no inbound adapter lists it.

- `BnestApp.Release` permanently lists `BnestApp.SqliteRepo`, `Ecto.Migrator` and `Ecto.Adapters.SQL`: release
  migrations are infrastructure entry points that `tools/deployment.mjs` evaluates by name, and scan rule L1
  exempts them.

## The Layering Scan

`apps/bnest-app/test/integration/architecture/hexagonal_layering_test.exs` is an integration ExUnit test. It reads
source files, which the unit layer's `BoundaryPolicy` forbids at that layer. It parses each file under `lib/` with
`Code.string_to_quoted/2` and walks the AST, so comments and strings never match. Rule L4's `BnestApp.Storage.Records`
clause has a temporary `@legacy_records_callers` allow-list: `UserAuth` and `ThemeController` until U6,
`SifatAllahLive` until U7, `ChatLive` until U8. Those units remove their entries, and U14 requires the list empty.

| Rule                                  | Applies to                                                                                                                                               | Fails when a module calls                                                                                                                                                                                       |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L1: effects only in adapters          | every module except `*.Adapters.*`, `BnestApp.SqliteRepo`, `BnestApp.Application`, `BnestApp.Release.*`, `BnestAppWeb.Endpoint`, `BnestAppWeb.Telemetry` | `File`, `Port`, `System.cmd/2,3`, `System.get_env/1,2`, `System.fetch_env/1`, `:os`, `:file`, `Req`, `Ecto.Adapters.SQL`, `Ecto.Migrator`, `Ecto.UUID`, `Exqlite`                                               |
| L2: domain is pure                    | `*.Domain.*`                                                                                                                                             | everything in L1, plus `DateTime.utc_now`, `System.monotonic_time`, `Process`, `GenServer`, `Phoenix`, `Logger`                                                                                                 |
| L3: every core module is in a context | `lib/bnest_app/**`                                                                                                                                       | it is unclassified: its first two namespace segments are not a declared context, `SqliteRepo`, `Application`, `Release`, `Mailer` or the root (enforced only once `@legacy_exports` is empty; U14 turns it on)  |
| L4: inbound adapters are thin         | `BnestAppWeb.*`, `BnestAppCli` Mix tasks                                                                                                                 | any `BnestApp.*.Adapters.*`, `BnestApp.*.Ports.*`, `BnestApp.Storage.Records`, or `BnestApp.SqliteRepo` reference (complements `boundary`, which ignores bare alias references unless `check: [aliases: true]`) |

While a context is still legacy, its modules match the scan's `@legacy_modules` allow-list. The scan asserts that
every `@legacy_exports` entry is also in `@legacy_modules`; `@legacy_modules` may hold more, namely legacy modules
that only other legacy modules call. Both lists shrink together.

## Test Support Classification

Test-support modules compile in `MIX_ENV=test` (`elixirc_paths(:test)`), so `boundary` classifies them as well. They
legitimately reach internals: an integration driver seeds SQLite, and a contract suite drives an adapter directly. Each
top-level test-support module declares itself an ignored top-level boundary:

```elixir
use Boundary, top_level?: true, check: [in: false, out: false]
```

That covers `BnestApp.Behaviour` (a new one-line namespace module under `test/behaviour/` that holds every
`BnestApp.Behaviour.*` driver), `BnestApp.TestRuntimeRoot`, `BnestApp.TestIdentity`, `BnestApp.SchemaSourceScan`,
`BnestApp.TestBackupDestination`, the Codex fixtures, `BnestAppWeb.ConnCase`, and the new `BnestApp.Test.InMemory` and
`BnestApp.Test.Contracts` namespaces from [004](004-test-doubles-and-contract-suites.md). Test-layer purity stays with
the existing `BoundaryPolicy` scan, which U3 extends so a unit file referencing `BnestApp.SqliteRepo` or a non-in-memory
`*.Adapters.*` module fails it.

## Coverage Configuration

`mix.exs` `test_coverage` currently lists about 70 `boundary_adapters` modules by name. U3 replaces those entries with a
pattern:

- `ignore_modules: [~r/\.Adapters\./]` covers every outbound and inbound adapter. Elixir's cover tool accepts regexes in
  `ignore_modules`.
- Named entries remain for the inbound web modules, `BnestApp.Application`, `BnestApp.SqliteRepo`, `BnestApp.Release.*`
  and the CLI tasks.
- Facades and domain modules are then **inside** the 99% unit threshold. Several of them (`BnestApp.Identity`,
  `PushNotifications`, `Scheduler`, `Backup`) are excluded today because they performed I/O. Each context unit adds the
  unit tests that bring its facade under the threshold, using in-memory adapters.
