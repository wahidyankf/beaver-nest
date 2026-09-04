# ex-bdd

`ex-bdd` is Beaver Nest's independently maintained Gherkin BDD engine for Elixir and ExUnit. It owns feature parsing, scenario expansion, step discovery, runtime execution, and static behaviour-completeness verification. Applications own their feature files, step definitions, and boundary adapters.

## Fork origin and license

This library began as a fork of [`huddlz-hq/cucumber`](https://github.com/huddlz-hq/cucumber) version 1.0.0 at commit [`114aceb7ed6a3e95eb496971e8a331a8a4b81a64`](https://github.com/huddlz-hq/cucumber/commit/114aceb7ed6a3e95eb496971e8a331a8a4b81a64), copyright 2024 Micah Woods, under the MIT License.

The fork is now maintained as an independent Beaver Nest library. It does not promise source, API, configuration, or implementation compatibility with upstream. See [UPSTREAM.md](UPSTREAM.md) and [LICENSE](LICENSE).

## Development

Applications add `{:ex_bdd, path: "../../libs/ex-bdd", only: :test}` and compile a recursively discovered corpus from their test helper:

```elixir
ExBdd.compile_features!(
  features: ["../../specs/example/app/behaviours/**/*.feature"],
  steps: ["test/behaviour/steps/**/*.exs"],
  support: ["test/behaviour/support/unit.exs"],
  case_template: ExUnit.Case
)
```

`ExBdd.verify_features!/1` performs the static completeness check without executing scenarios. It requires non-empty features, expanded scenarios with explicit `When` and `Then`, exactly one binding per step, and no unused binding. `:case_template` lets an integration adapter use a project-specific ExUnit case template such as a Phoenix connection case.

Run tasks from the repository root through the workspace [HIPPO](../../repo-governance/development/resource-aware-development.md):

```sh
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t typecheck
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t lint
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:unit
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:integration
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:coverage:unit
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:coverage:integration
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:coverage:engine
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:coverage
./hippo run --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:quick
```

`test:unit` executes only `test/unit/`: in-process tests whose OS-facing dependencies are replaced by doubles. `test:integration` executes only `test/integration/`: real fixture discovery, file output, code loading, and same-machine process coordination, with no network. The integration bootstrap compiles the vendored feature corpus only in that layer. `test:quick` runs typecheck, lint, unit execution, and unit coverage; integration remains scheduled and outside pre-push quick checks. ExBdd owns no public system journey, so an E2E project and `test:e2e` target are intentionally inapplicable.

Every numeric slice fails below 99% total line coverage. The unit denominator owns expression matching, step-definition and step-error behaviour, pickle expansion, verification delegation, and production data/error values. The integration denominator owns discovery, compilation, parsing, parameter registration, message emission, run coordination, and public verification. Cross-layer orchestration modules that cannot independently reach 99% in either boundary-correct slice remain included in `test:coverage:engine`; that target runs both layer trees and enforces 99% over the complete retained production engine, so scoped exclusions cannot create an unmeasured gap. `test:coverage` sequentially composes all three named slices. Test-only support modules are excluded from every production denominator. Reports are written to `cover/unit/`, `cover/integration/`, and `cover/engine/`.

Important paths:

- `lib/ex_bdd/` contains discovery, parsing, verification, compilation, and runtime code.
- `test/unit/ex_bdd/` contains executable resource-free unit tests.
- `test/integration/ex_bdd/` contains executable local-resource integration tests.
- `test/features/`, `test/fixtures/`, and `test/support/` contain shared non-executable corpus, fixtures, bindings, and support.
- `test/fixtures/cck/` contains the retained Cucumber Compatibility Kit fixtures.
- `UPSTREAM.md` records the exact fork provenance and divergence policy.

See the [repository README](../../README.md) and [BDD standard](../../repo-governance/development/behaviour-driven-development.md) for workspace-wide conventions.
