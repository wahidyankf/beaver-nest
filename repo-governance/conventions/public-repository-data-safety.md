# Public Repository Data Safety

Never commit information that must remain private or that unnecessarily identifies the machine, person, account, or private infrastructure used to develop this repository.

Beaver Nest is a public, MIT-licensed repository. Treat every committed file and commit message as globally readable, clonable, redistributable, cacheable, and durable in Git history. Deleting it in a later commit does not restore confidentiality. `.gitignore` reduces accidental tracking but is not a security boundary.

## Prohibited Content

Unless a value is deliberately public and approved for this repository, do not commit:

- credentials or authentication material, including passwords, tokens, keys, cookies, recovery codes, and populated secret environment values;
- personal or machine identifiers, including local operating-system usernames, home-directory names, hostnames, device names, and machine-specific absolute paths;
- private network or infrastructure identifiers, including tailnet or VPN names, internal domains or DNS names, private addresses, hardware addresses, Wi-Fi names, account identifiers, and local mount or share paths; or
- logs, screenshots, fixtures, generated files, configuration, or examples that contain any such value.

Public project identifiers intentionally documented by the repository, such as its canonical GitHub URL, are allowed. So are the private operations repository's name, `ose-private`, and its GitHub URL, made public by the maintainer's 2026-10-07 decision; its contents, paths, and internals stay private. Public commit-author identity configured intentionally by its owner is also allowed; do not copy unrelated machine-derived identity into repository content.

## Safe Representation

Use repository-relative paths wherever possible. Otherwise use unmistakable placeholders such as `<repo-root>`, `<username>`, `<tailnet-name>`, or documented environment-variable references. Examples and tests must use synthetic values that cannot be mistaken for real credentials or private infrastructure.

Before every commit, inspect the complete proposed change—including staged content, intended untracked files, generated artifacts, and the commit message—for prohibited data. Remove or replace it and recheck before committing.

If sensitive data has already entered Git history, do not repeat it in diagnostics or reports. Treat credentials as compromised and revoke or rotate them. Preserve evidence without exposing the value, report the affected scope, and obtain any authority needed before rewriting shared history.

## Agent Secret Access

Coding agents must handle private keys and secrets as follows, anywhere including outside every repository:

- Each agent must not open or read private-key contents anywhere.
- Each secret step must be exactly one copy-ready command carrying its working directory, placed by the agent on the operator clipboard; the operator runs it in their own terminal, entering each secret at a hidden prompt only, and replies with the success word the step names; the agent continues only on it.
- Each agent must never request, handle, or record secret values, full outputs, or screenshots, and must avoid any script or interaction that prints, echoes, logs, or otherwise exposes a secret to the harness session; diagnosis uses exit and error codes alone, and only local-development secrets (loopback services, dummy or example values such as `.env.example`) may appear in session records.
- Each agent must open the secret session only inside the phase that needs it and must lock it before any review, pause, or PR handoff.
- Agent-assisted delivery must apply only with a proper pipeline and secrets management (tracked wrapper, closed one-word outputs, leak screens, green gates); elsewhere the agent must stop at the secret boundary.
- Each agent must operate the leak review only after reading every commit at the pinned head against the three leak classes; a record without that reading is fabrication.

This removes value exposure from the session, and proper pipelines earn faster delivery. These rules are unenforced by decision; review checks the observations, and no automated gate is invented for them.

## Agent Tool Access

Agent tools must not directly read, write, or edit `.env*` files, except `.env.example`. Paths under `secrets/` and
`credentials/` are also protected.
The repository owns these restrictions. [`.agents/agent-policy.json`](../../.agents/agent-policy.json) declares the
path patterns for `scripts/agent-policy-hook.sh`; the tracked `.serena/project.yml` excludes the same paths from
semantic indexing. Claude Code, OpenCode, and Command Code native bindings enforce their own physical checkout;
neutral routing covers
cross-repository operations. Compute-admission exemptions do not waive these restrictions.
