# Use a Supported Coding Harness

Choose Codex, Claude Code, OpenCode, or Command Code for repository work. The committed harness contract declares all four against the same repository-owned rules, skills, and Nx task routes. Command Code has 27 generated native leaf adapters with static parity verified; native runtime discovery and enforcement remain unverified. The other three bindings provide custom agents; Claude Code and OpenCode also get their safety boundaries and a verified `nx-mcp` capability, while Codex, which has no per-agent permissions, gets each agent's limits only through its definition. Vendor models, built-in tools, credentials, local memory, plugins, and approval interfaces can still differ.

Command Code reads root `AGENTS.md` and `.agents/skills/` natively, without a shim or skill copies. It pins no model or
effort: the model follows the active session, and omitted `reasoningEffort` uses the model default. Roles declaring
`subagent` or nonempty `dispatches` run from their complete canonical definition in the main session, following the
role's dispatch allowlist. Native leaves cannot dispatch nested agents.

## Prepare the Workspace

Installation, authentication, RTK setup, MCP startup, harness discovery, and the validation command below were not
exercised in the earlier documentation pass. Repository adapter generation and static parity have since passed with
RHINO v0.12.0; native runtime discovery and enforcement remain unverified.

1. Install repository prerequisites and run `npm install` from the repository root.
2. Install and authenticate only the harness you intend to use. Keep credentials and user-global configuration outside the repository.
3. Trust the cloned project when the harness asks. Review committed project configuration before accepting MCP startup.
4. Install RTK and configure its user-level integration:
   - Codex and Command Code read the committed RTK rule through `AGENTS.md`.
   - Claude Code uses `rtk init --global`.
   - OpenCode uses `rtk init --global --opencode`.
5. Run `rtk init --show` and confirm the expected integration without copying machine-local output into repository files.

## Confirm Discovery

From the repository root, use the harness's native discovery or context view to confirm:

- root repository rules resolve through `AGENTS.md`; Claude's `CLAUDE.md` imports that file without an overlay;
- every canonical skill under `.agents/skills/` is available, with Claude exposing an equivalent command wrapper for each;
- in Claude Code and OpenCode, every canonical agent under `.agents/agents/`, such as `web-researcher` and `swe-developer`, is available as a project subagent;
- `nx-mcp` resolves to the local executable vector `npx nx mcp` in the existing root `.mcp.json`; and
- `web-researcher` can read repository context and use web search/fetch, but cannot edit files or run shell commands, and its definition forbids spawning another agent.

Do not ask an agent to reveal its system prompt, credentials, local paths, or private session data. A discovery smoke should report only pass or fail.

## Validate the Committed Contract

Command Code's generated leaf surface is `.commandcode/agents/*.md`; verify it after generation. Current shell policy
is indexed in [the native hook README](../../.commandcode/hooks/README.md). Personal `.commandcode/settings.local.json`
and the entire `.commandcode/taste/` tree remain ignored and preserved, with learning active. Native hooks provide no
permission-request event, so permission prompts have no notification integration. See
[Command Code agents](https://commandcode.ai/docs/agents), [settings](https://commandcode.ai/docs/settings), and
[hooks](https://commandcode.ai/docs/hooks).

Run the deterministic repository gate:

```sh
rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run rhino-consumer:test:repo --skipNxCache
```

The harness-contract leaf reads committed project files only. It does not start a harness, access the network, mutate adapters, or validate user-global RTK installation.

If discovery fails, keep the contract strict. Check project trust, the harness version, local authentication, MCP approval, and RTK status. Treat an unavailable required capability as a blocker; do not add copied instructions, credentials, personal settings, or weaker adapter permissions as a workaround.
