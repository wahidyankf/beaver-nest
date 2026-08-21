# Public Repository Data Safety

Never commit information that must remain private or that unnecessarily identifies the machine, person, account, or private infrastructure used to develop this repository.

Beaver Nest is a public, MIT-licensed repository. Treat every committed file and commit message as globally readable, clonable, redistributable, cacheable, and durable in Git history. Deleting it in a later commit does not restore confidentiality. `.gitignore` reduces accidental tracking but is not a security boundary.

## Prohibited Content

Unless a value is deliberately public and approved for this repository, do not commit:

- credentials or authentication material, including passwords, tokens, keys, cookies, recovery codes, and populated secret environment values;
- personal or machine identifiers, including local operating-system usernames, home-directory names, hostnames, device names, and machine-specific absolute paths;
- private network or infrastructure identifiers, including tailnet or VPN names, internal domains or DNS names, private addresses, hardware addresses, Wi-Fi names, account identifiers, and local mount or share paths; or
- logs, screenshots, fixtures, generated files, configuration, or examples that contain any such value.

Public project identifiers intentionally documented by the repository, such as its canonical GitHub URL, are allowed. Public commit-author identity configured intentionally by its owner is also allowed; do not copy unrelated machine-derived identity into repository content.

## Safe Representation

Use repository-relative paths wherever possible. Otherwise use unmistakable placeholders such as `<repo-root>`, `<username>`, `<tailnet-name>`, or documented environment-variable references. Examples and tests must use synthetic values that cannot be mistaken for real credentials or private infrastructure.

Before every commit, inspect the complete proposed change—including staged content, intended untracked files, generated artifacts, and the commit message—for prohibited data. Remove or replace it and recheck before committing.

If sensitive data has already entered Git history, do not repeat it in diagnostics or reports. Treat credentials as compromised and revoke or rotate them. Preserve evidence without exposing the value, report the affected scope, and obtain any authority needed before rewriting shared history.
