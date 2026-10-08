# Native Repository Binding

The profile in [`repo-config.yml`](../repo-config.yml) selects native leaf agents. Their generated adapters import
the authoritative definitions in [`.agents/agents/`](../.agents/README.md); change those sources or the profile and
regenerate with `./rhino harness adapters generate`. Validate with `./rhino harness adapters validate`.

## Contents

- [Settings](settings.json) — One repository policy endpoint and any existing repository event hooks.
- [Hooks](hooks/README.md) — Native policy transport and synthetic selector regression.
- [Agent catalog](agents/catalog.json) — Generated native agent selection.

Repository policy remains local; personal approval defaults and FERRET capture belong to global configuration.
Source settings alone do not prove installed CLI discovery or live execution.
