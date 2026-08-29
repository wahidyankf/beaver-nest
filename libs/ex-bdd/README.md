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

Run tasks from the repository root through the resource guard:

```sh
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p ex-bdd -t typecheck
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p ex-bdd -t lint
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:unit
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:coverage
npm run resource:run -- --class ephemeral -- npm exec -- nx run -p ex-bdd -t test:quick
```

The coverage target includes the complete retained production engine and must remain at least 99% line-covered. Test-only support modules are excluded from the production denominator.

Important paths:

- `lib/ex_bdd/` contains discovery, parsing, verification, compilation, and runtime code.
- `test/ex_bdd/` contains unit, behavior, message, and compatibility-kit tests.
- `test/fixtures/cck/` contains the retained Cucumber Compatibility Kit fixtures.
- `UPSTREAM.md` records the exact fork provenance and divergence policy.

See the [repository README](../../README.md) and [BDD standard](../../repo-governance/development/behaviour-driven-development.md) for workspace-wide conventions.
