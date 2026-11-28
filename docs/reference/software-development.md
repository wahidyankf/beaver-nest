# Software Development Stacks

This page maps each project to the stack packs whose rules apply to its code. A stack pack is a standard, which holds
the rules, plus a skill, which guides an agent applying them. The machine-readable source is the
`extensions.software-development` inventory in [`repo-config.yml`](../../repo-config.yml); the
[repository adapter](../../repo-governance/development/quality/stacks/repository-adapter.md) records every local
decision and deviation. Commands and test layers stay in each project's README.

## Projects

- **[bnest-app](../../apps/bnest-app/README.md)**
  - Kind: app
  - Stacks: Elixir, Phoenix LiveView, JavaScript, TypeScript
- **[bnest-app-be-e2e](../../apps/bnest-app-be-e2e/README.md)**
  - Kind: app
  - Stacks: TypeScript
- **[bnest-app-fe-e2e](../../apps/bnest-app-fe-e2e/README.md)**
  - Kind: app
  - Stacks: TypeScript
- **[rhino-consumer](../../apps/rhino-consumer/README.md)**
  - Kind: tooling
  - Stacks: Nx
- **[public-safety](../../scripts/public-safety/README.md)**
  - Kind: tooling
  - Stacks: Shell
- **`scripts/`, `.github/scripts/`, `.claude/hooks/`**
  - Kind: tooling
  - Stacks: Shell
- **the workspace root**
  - Kind: tooling
  - Stacks: Nx

## Packs

- **Elixir**
  - Standard: [Elixir standards](../../repo-governance/development/quality/stacks/elixir-standards.md)
  - Skill: [programming-elixir](../../.agents/skills/programming-elixir/SKILL.md)
- **Phoenix LiveView**
  - Standard: [Phoenix LiveView
    standards](../../repo-governance/development/quality/stacks/phoenix-liveview-standards.md)
  - Skill: [framework-phoenix-liveview](../../.agents/skills/framework-phoenix-liveview/SKILL.md)
- **JavaScript**
  - Standard: [JavaScript standards](../../repo-governance/development/quality/stacks/javascript-standards.md)
  - Skill: [programming-javascript](../../.agents/skills/programming-javascript/SKILL.md)
- **TypeScript**
  - Standard: [TypeScript standards](../../repo-governance/development/quality/stacks/typescript-standards.md)
  - Skill: [programming-typescript](../../.agents/skills/programming-typescript/SKILL.md)
- **Shell**
  - Standard: [Shell standards](../../repo-governance/development/quality/stacks/shell-standards.md)
  - Skill: [programming-shell](../../.agents/skills/programming-shell/SKILL.md)
- **Nx**
  - Standard: [Nx standards](../../repo-governance/development/quality/stacks/nx-standards.md)
  - Skill: [tooling-nx](../../.agents/skills/tooling-nx/SKILL.md)

Every project also follows the language-neutral
[type and boundary safety](../../repo-governance/development/quality/code/type-and-boundary-safety.md) and
[meaningful coverage](../../repo-governance/development/quality/testing/meaningful-coverage.md) standards. Application
code in `bnest-app` is placed by the
[hexagonal architecture](../../repo-governance/development/quality/code/hexagonal-architecture.md) standard.

## Agents

The `swe-developer`, `swe-reviewer`, and `swe-debugger` agents under `agents/` build, audit, and debug code in these
projects; [SWE delegation](../../repo-governance/conventions/swe-delegation.md) routes work to the whole `swe-*` family.
Each reads a project's inventory entry and loads the standard and skill of every listed stack before it starts.
