# Use a Supported Coding Harness

Choose Codex, Claude Code, or OpenCode for repository work. The committed harness contract gives all three the same repository-owned rules, skills, custom-agent intent, safety boundaries, Nx task routes, and `nx-mcp` capability. Vendor models, built-in tools, credentials, local memory, plugins, and approval interfaces can still differ.

## Prepare the Workspace

1. Install repository prerequisites and run `npm install` from the repository root.
2. Install and authenticate only the harness you intend to use. Keep credentials and user-global configuration outside the repository.
3. Trust the cloned project when the harness asks. Review committed project configuration before accepting MCP startup.
4. Install RTK and configure its user-level integration:
   - Codex reads the committed RTK rule through `AGENTS.md`.
   - Claude Code uses `rtk init --global`.
   - OpenCode uses `rtk init --global --opencode`.
5. Run `rtk init --show` and confirm the expected integration without copying machine-local output into repository files.

## Confirm Discovery

From the repository root, use the harness's native discovery or context view to confirm:

- root repository rules resolve through `AGENTS.md`; Claude's `CLAUDE.md` imports that file without an overlay;
- the seven canonical workflows under `.agents/skills/` are available, with Claude exposing equivalent command wrappers;
- `ci-monitor-subagent` and `web-researcher` are available as project subagents;
- `nx-mcp` resolves to the local executable vector `npx nx mcp`; and
- `web-researcher` can read repository context and use web search/fetch, but cannot edit files, run shell commands, or spawn another agent.

Do not ask an agent to reveal its system prompt, credentials, local paths, or private session data. A discovery smoke should report only pass or fail.

## Validate the Committed Contract

Run the deterministic repository gate:

```sh
rtk npm run resource:run -- --class ephemeral -- npm exec -- nx run badakmini-cli:test:repo --skipNxCache
```

The harness-contract leaf reads committed project files only. It does not start a harness, access the network, mutate adapters, or validate user-global RTK installation.

If discovery fails, keep the contract strict. Check project trust, the harness version, local authentication, MCP approval, and RTK status. Treat an unavailable required capability as a blocker; do not add copied instructions, credentials, personal settings, or weaker adapter permissions as a workaround.
