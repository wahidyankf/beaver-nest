# Software Development Stacks

This page maps each project to the stack packs whose rules apply to its code. A stack pack is a standard, which holds
the rules, plus a skill, which guides an agent applying them. The machine-readable source is the
`extensions.software-development` inventory in [`repo-config.yml`](../../repo-config.yml); the
[repository adapter](../../repo-governance/development/quality/stacks/repository-adapter.md) records every local
decision and deviation. Commands and test layers stay in each project's README.

## Projects

| Project                                                   | Kind    | Stacks                                           |
| --------------------------------------------------------- | ------- | ------------------------------------------------ |
| [bnest-app](../../apps/bnest-app/README.md)               | app     | Elixir, Phoenix LiveView, JavaScript, TypeScript |
| [ex-bdd](../../libs/ex-bdd/README.md)                     | library | Elixir                                           |
| [bnest-app-be-e2e](../../apps/bnest-app-be-e2e/README.md) | app     | TypeScript                                       |
| [bnest-app-fe-e2e](../../apps/bnest-app-fe-e2e/README.md) | app     | TypeScript                                       |
| [rhino-consumer](../../apps/rhino-consumer/README.md)     | tooling | Nx                                               |
| [public-safety](../../scripts/public-safety/README.md)    | tooling | Shell                                            |
| `scripts/`, `.github/scripts/`, `.claude/hooks/`          | tooling | Shell                                            |
| the workspace root                                        | tooling | Nx                                               |

## Packs

| Stack            | Standard                                                                                                     | Skill                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Elixir           | [Elixir standards](../../repo-governance/development/quality/stacks/elixir-standards.md)                     | [programming-elixir](../../.agents/skills/programming-elixir/SKILL.md)                 |
| Phoenix LiveView | [Phoenix LiveView standards](../../repo-governance/development/quality/stacks/phoenix-liveview-standards.md) | [framework-phoenix-liveview](../../.agents/skills/framework-phoenix-liveview/SKILL.md) |
| JavaScript       | [JavaScript standards](../../repo-governance/development/quality/stacks/javascript-standards.md)             | [programming-javascript](../../.agents/skills/programming-javascript/SKILL.md)         |
| TypeScript       | [TypeScript standards](../../repo-governance/development/quality/stacks/typescript-standards.md)             | [programming-typescript](../../.agents/skills/programming-typescript/SKILL.md)         |
| Shell            | [Shell standards](../../repo-governance/development/quality/stacks/shell-standards.md)                       | [programming-shell](../../.agents/skills/programming-shell/SKILL.md)                   |
| Nx               | [Nx standards](../../repo-governance/development/quality/stacks/nx-standards.md)                             | [tooling-nx](../../.agents/skills/tooling-nx/SKILL.md)                                 |

Every project also follows the language-neutral
[type and boundary safety](../../repo-governance/development/quality/code/type-and-boundary-safety.md) and
[meaningful coverage](../../repo-governance/development/quality/testing/meaningful-coverage.md) standards.

## Agents

The `swe-code-maker`, `swe-code-checker`, and `swe-code-fixer` agents under `.agents/agents/` build, audit, and repair
code in these projects. Each reads a project's inventory entry and loads the standard and skill of every listed stack
before it starts.
