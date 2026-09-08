# Coding-Harness Parity Verification

Use this workflow to evaluate whether Codex, Claude Code, and OpenCode currently satisfy the repository-owned [coding-harness contract](../conventions/coding-harness-contract.md). It is a read-only verification workflow; use the [coding-harness contract change workflow](coding-harness-contract-change.md) when remediation or contract evolution is requested.

## Prerequisites

- Read the coding-harness contract and keep its repository-owned scope distinct from vendor prompts, models, credentials, plugins, local memory, and user-global configuration.
- Record the current revision and worktree status. Existing changes remain user-owned and must not be modified by verification.
- Use the resolved Nx target rather than invoking the pinned executable directly.

## Procedure

### 1. Establish the verification baseline

Record `git status --short` and resolve the project configuration:

```sh
npm exec -- nx show project rhino-consumer --json
```

Confirm that `test:repo` contains the `harness parity validate` command. Treat later repository changes as invalidating results from this baseline.

### 2. Review the canonical topology

Confirm the intended sources and adapters before interpreting the gate:

- root `AGENTS.md` and the exact root `CLAUDE.md` import;
- every `.agents/skills/<name>/` bundle and its single Claude command wrapper;
- every `.agents/agents/<name>.md` and one matching adapter per harness; and
- `.codex/config.toml`, `.mcp.json`, and `opencode.json` declarations for the credential-free `npx nx mcp` capability.

Do not infer parity from matching names or counts. Content digests, canonical routes, native permissions, denies, constraints, and executable behaviour remain authoritative.

### 3. Run the deterministic repository proof

Run the required gate without accepting cached results:

```sh
./hippo run --class ephemeral --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo --skipNxCache
```

Record the exit status, contract digest, harness count, skill count, agent count, and capability count. On failure, review every finding by kind, field, harness, and path rather than stopping at the summary count.

### 4. Evaluate the enforcement when needed

The validator is not built here, so this repository cannot evaluate it. What it can evaluate is the pin and the bootstrap that resolves it:

```sh
./hippo run --class ephemeral --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:bootstrap
```

RHINO's own unit, integration, and process-level proof runs in [its repository](https://github.com/wahidyankf/rhino) against the release named in `rhino.lock`. A parity verdict here is a claim about this repository at that pinned release; it is not a claim about an unreleased change to the validator.

### 5. Bound runtime claims

CLI presence and versions may be recorded as a local availability smoke check. Do not present them as proof that vendor discovery, model behaviour, or user-global integrations honor the repository contract. Report runtime discovery as separately verified, not assessed, unavailable, or failed.

### 6. Report the verdict

Report repository parity as:

- **pass** only when the uncached deterministic gate succeeds at the recorded baseline;
- **fail** when any contract finding exists;
- **blocked** when the gate cannot execute or required evidence is unreadable; or
- **not assessed** when verification was not run.

Include the commands run, digest and reconciled counts, worktree state, optional behaviour-test results, runtime-discovery scope, and unresolved risks. Do not broaden a repository-parity pass into a claim about excluded vendor or local state.

## Recovery

If verification fails, preserve the findings and use the coding-harness contract change workflow to repair the canonical source or native adapter. Never weaken the validator, remove a deny, or exclude a repository path merely to obtain a pass. Rerun this workflow from a newly recorded baseline after remediation.
