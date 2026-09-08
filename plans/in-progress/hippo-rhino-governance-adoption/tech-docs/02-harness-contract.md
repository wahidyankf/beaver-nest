# The Harness Contract

Three harnesses — Claude Code, Codex, OpenCode — reach the same rules, the same skills, and the same agent in each repository, with no Nx and no capability server.

## Why No Capability Server

This repository's contract requires every harness to declare the credential-free `npx nx mcp` vector. Neither CLI uses Nx, and HIPPO's rules forbid introducing it, so that requirement cannot travel.

RHINO's schema permits its absence directly: `required-mcp` is optional, and the reference states that a repository with harnesses may have no canonical skills, no canonical agents, and no capability server, because each is something a repository may genuinely not have. It also enforces the pairing — `required-mcp` obliges a `capability` block on every harness, and declaring either half alone is refused. So both repositories declare neither half, and no `.mcp.json` is created.

Nothing is lost. The parity claim in this family was never mainly about MCP; it was about one instruction body, one canonical prompt per agent, one skill bundle, and adapters that route rather than copy. All of that survives.

## Canonical Roster

`skills-root` and `agents-root` are both declared, which obliges `skill-route`, `agent-route`, a `declaration` block, and an `agent-adapter` on every harness. That is more machinery than a skills-only contract, and it is chosen deliberately: the `denies` translations — the ones that prove an adapter cannot grant what the canon forbids — are only exercised when a canonical agent exists. A contract whose hardest path is never taken is a contract that has not been tested.

### Skills, three per repository

| Skill                    | What it encodes                                                                                                                                                                                                                          | Why this one                                                                                                                                 |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `worktree-to-pr`         | Create the worktree, install to activate hooks, branch, commit, push, open the pull request, wait for the gate, merge, delete the branch and remove the worktree.                                                                        | The workflow this plan introduces. Nobody has done it in these repositories yet, which is exactly when a skill earns its place.              |
| `spec-impact-assessment` | Assess `specs/behaviours/` and `specs/architecture.md` before a change; write Gherkin first; prove the binding fails for the stated reason; record a verified no-op rather than churn an unaffected specification.                       | Both `AGENTS.md` files already mandate this on _every_ change, and it exists only as prose. The highest-frequency rule in either repository. |
| `release-cut`            | HIPPO: `scripts/build-release.sh <version> <commit> <output-dir>`. RHINO: `cargo xtask dist`, then `cargo xtask checksums`. Both: a tag must reach the default branch, a tag is never replaced, checksum verification is never weakened. | Highly proceduralized, performed roughly eight times each so far, and the one procedure where a mistake is permanent.                        |

Each skill is a canonical bundle under `.agents/skills/<name>/SKILL.md`, with supporting files where the procedure needs them. Content is repository-specific: `release-cut` in HIPPO and `release-cut` in RHINO share a name and nothing else, which is correct — the drift policy applies to prose, and these are commands.

### Agent, one per repository

`gherkin-implementation-reviewer`, under `.agents/agents/`. Read-only by declaration: it `requires` repository read, and `denies` repository write, shell, and nested agents. It reviews changed Gherkin and its bindings against the repository's own rules — no placeholders, no no-ops, no outcome tables, every scenario bound at the unit adapter, any integration or E2E exemption naming a concrete boundary rather than difficulty, runtime, flakiness, or cost.

A reviewer is the right first agent precisely because its value comes from what it may not do. If any adapter quietly grants `Bash` or `Edit`, the parity check must fail — and that failure is the proof that the deny translations work.

## Adapter Contracts

`declaration` uses the same field names this repository uses — `grants: requires`, `denials: denies`, `limits: constraints`, `fixed: { mode: subagent }` — because RHINO reads those names from configuration and a list read under a name nobody wrote comes back empty rather than missing. Same names, same reason, independently chosen.

| Harness  | Agent adapter                | Skill adapter | Notes                                                                              |
| -------- | ---------------------------- | ------------- | ---------------------------------------------------------------------------------- |
| claude   | `.claude/agents/{name}.md`   | to be settled | Front matter, `route-field: body`, translations mapping the canon onto `tools`.    |
| codex    | `.codex/agents/{name}.toml`  | to be settled | TOML, `route-field: developer_instructions`, `fixed: { sandbox_mode: read-only }`. |
| opencode | `.opencode/agents/{name}.md` | to be settled | Front matter, `fixed: { mode: subagent }`, translations mapping onto `permission`. |

The `tools` and `permission` translation tables are carried over from this repository minus every `nx-mcp` entry, because the capability vocabulary shrinks to `repository-read`, `repository-write`, `shell`, and `nested-agent` — the four this agent actually turns on and off.

## Prohibitions

Both repositories prohibit `**/AGENTS.override.md`, nested `**/AGENTS.md`, `.claude/rules/**/*.md`, `.cursorrules`, `**/.windsurfrules`, `**/GEMINI.md`, and `.github/copilot-instructions.md`. HIPPO additionally stops prohibiting `**/CLAUDE.md`, which becomes its declared instruction adapter; the boundary tightens overall.

Both also gain `prohibited-instruction-fields`, which this repository does not use and should: a competing always-on instruction written into a vendor's own settings file is the same violation as a second `CLAUDE.md`, just in JSON or TOML. The candidates are OpenCode's `instructions` array in `opencode.json` and the equivalent key in `.codex/config.toml`. RHINO treats an absent key and an explicitly empty one as answers rather than violations, and reports a file it cannot parse in its declared format instead of assuming it is clean — a source that cannot be ruled out has not been ruled out.

## Open Questions, To Be Settled Against the Binary

These are read from RHINO's reference documentation and must be confirmed by running `rhino repo-config validate`, because the documentation is a description of the binary and the binary is the contract. Each is a delivery task, and each has a recorded fallback.

- **Does a harness entry accept a skill adapter without an agent adapter, and vice versa?** The reference makes `agent-adapter` required alongside `agents-root` and leaves `skill-adapter` optional, which implies a harness may express agents but not skills. If a harness has no native skill surface, that asymmetry is the honest declaration; the alternative — declaring a skill adapter pointing at a surface the vendor does not read — would be a parity claim that reconciles nothing.
- **What is each harness's native skill surface?** Claude Code supports a directory-per-document form that RHINO explicitly handles. Codex and OpenCode must be established by inspection rather than assumed from this repository's `.claude/commands/` choice, which is a Claude-only wrapper.
- **Does the canonical instruction file survive its own prohibition glob?** `canonical.instruction: AGENTS.md` alongside a prohibited `**/AGENTS.md` must exempt the canonical one. Confirm before writing it into two repositories.
- **Is `capabilities` permitted to be non-empty with no `required-mcp`?** The pairing rule binds `required-mcp` to the per-harness `capability` block. The `capabilities` vocabulary is what agents draw from and translations fire on, so it must be declarable independently. If it is not, the agent's deny translations cannot be expressed and the roster reduces to skills only.

A refusal on any of these in RHINO is a RHINO defect or a deliberate schema limit. RHINO is sequenced first so the answer arrives from a source build, before HIPPO's pinned `v0.1.3` has to express the same shape.

## Related

- [Technical design](README.md)
- [The governance restructure](01-governance-restructure.md)
- [The gate and ruleset design](04-pr-gate-and-ruleset.md)
