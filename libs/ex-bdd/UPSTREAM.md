# Upstream provenance

- Upstream: [`huddlz-hq/cucumber`](https://github.com/huddlz-hq/cucumber)
- Imported version: `1.0.0`
- Imported commit: `114aceb7ed6a3e95eb496971e8a331a8a4b81a64`
- Forked on: 2026-08-23
- Original copyright: Copyright (c) 2024 Micah Woods
- License: MIT; preserved in [LICENSE](LICENSE)

The initial import retained the runtime, Gherkin parser, scenario compiler, expression and hook support, messages support, tests, and Cucumber Compatibility Kit fixtures. Upstream publishing, release, and installation automation was not imported.

Beaver Nest subsequently renamed the application and namespaces to `ex_bdd` and `ExBdd`, added strict behaviour-completeness verification, and added configurable ExUnit case templates. This fork is intentionally free to diverge and does not maintain upstream compatibility.
