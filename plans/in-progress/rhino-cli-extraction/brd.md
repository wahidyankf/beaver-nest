# Business Requirements

## Goal

Own the repository-hygiene contract once, in one independently released tool, so that every repository the maintainer runs can enforce the same documentation rules without each one carrying its own validator, its own toolchain, and its own copy of the logic.

## Roles

- **Maintainer:** authors governed Markdown and expects the same clear findings from one command, in any repository.
- **RHINO (upstream):** owns validator behaviour, the configuration schema, the CLI contract, exit codes, and immutable release artifacts. Owns no repository's policy.
- **Consuming repository:** owns its own policy values in `repo-config.yml`, pins one release by version, commit, and checksum, and decides when to move that pin.
- **BeaverNest routed service:** continues serving the household throughout and is never touched by this work.

## Required Outcomes

- Every check `apps/badakmini-cli` performs today — word budgets, directory maps, internal Markdown links, Mermaid accessibility and legibility, and coding-harness parity — is performed by the released `rhino` binary against this repository, driven entirely by declared configuration.
- The tool contains no BeaverNest path, tree name, word limit, harness name, or capability vocabulary as a built-in default. A repository that declares nothing gets a clear configuration error, never a silent BeaverNest assumption.
- That claim is proved by adoption, not assertion: RHINO validates its own repository — which has no governance tree, no plans tree, and an empty harness roster — before the first release is tagged, and continues to do so in CI.
- The scenario corpus that specifies this behaviour lives with the tool and executes at unit, integration, and process boundaries, so the four future consumer repositories inherit a specification rather than a folk understanding.
- BeaverNest consumes the tool through a pinned bootstrap that verifies both the archive checksum and the executable's embedded release identity before running it, and fails closed when either is wrong.
- After cutover, `apps/badakmini-cli`, `apps/badakmini-cli-e2e`, and the .NET toolchain they require are gone from this repository, and no rule, document, target, hook, or specification still names them.
- The maintainer's published RHINO artifacts cover macOS and Linux on both `amd64` and `arm64`, and a release tag is never replaced.
- A repository adopting RHINO can learn it, use it, and look things up without reading its source, through the same documentation model HIPPO already proves; and RHINO's own repository passes the checks RHINO performs.

## Non-goals

- Adopting RHINO in `grind-in-public`, `hippo`, `ose-public`, or `ose-private`. Their adoption is enabled here and executed elsewhere.
- Retiring or merging `ose-public`'s existing `apps/rhino-cli`. This plan aligns with its surface so that a future merge is a configuration port; it does not perform that merge.
- Adding validators, output formats, or repository-hygiene concerns that Badakmini does not implement today.
- Changing any governed content in order to make it pass. The corpus that passes today must pass after cutover; a rule change is a separate, explicitly authorized decision.
- Changing BeaverNest product behaviour, storage, deployment, or routing.

## Risks and Controls

- **Silent behaviour loss during rewrite.** Five validators and roughly 5,000 lines move languages at once. Control: the same 81-scenario corpus binds at three adapter levels before cutover, and the retired binary is deleted only after the new one has passed the full repository gate on the real corpus.
- **Word-count divergence.** The budget is a numeric gate; a different Unicode word-boundary or grapheme rule silently changes pass or fail on 49 governed files. Control: a direct count comparison across every governed file before the old binary is removed, retained as the single narrow numeric exception to the corpus-only proof strategy.
- **Regex dialect gap.** Badakmini's Mermaid and Markdown parsing leans on .NET regular expressions, which support constructs Rust's `regex` crate deliberately omits. Control: inventory every pattern and its required features before any port work begins; treat an unsupported construct as a design task, not an implementation surprise.
- **Unmaintained dependency.** The configuration format alignment points at YAML, whose best-known Rust binding is deprecated. Control: apply [dependency selection](../../../repo-governance/development/dependency-selection.md) with current primary-source evidence and record the decision before it is written into the schema.
- **Two-repository coordination.** BeaverNest cannot verify a pin that does not exist, and a bad release cannot be recalled. Control: strict phase ordering — upstream green, then tag, then pin, then cut over — and a rollback that restores the old pin rather than editing a published tag.
- **Public repository exposure.** RHINO is public and this repository is private. Control: apply the [public repository data-safety convention](../../../repo-governance/conventions/public-repository-data-safety.md) to everything moved upstream; move behaviour, never household paths, hostnames, or runtime values.
- **Enforcement gap during transition.** A window in which neither validator gates pushes would let governed content drift. Control: the pre-push hook moves from one gate to the other inside a single change, never through an ungated intermediate state.
