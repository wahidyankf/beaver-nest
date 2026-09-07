# Business Requirements

## Goal

Own the repository-hygiene contract once, in one independently released tool, so that every repository the maintainer runs enforces the same documentation rules without each one carrying its own validator, its own toolchain, and its own reimplementation of the logic. Three implementations in three languages already exist; this plan replaces two of them and stops the fourth from being written.

## Roles

- **Maintainer:** authors governed Markdown and expects the same clear findings from one command, in any repository.
- **RHINO (upstream):** owns validator behaviour, the configuration schema, the CLI contract, exit codes, and immutable release artifacts. Owns no repository's policy.
- **Consuming repository:** owns its own policy values in `repo-config.yml`, pins one release by version, commit, and checksum, and decides when to move that pin. Four adopt here: rhino, BeaverNest, HIPPO, and grind-in-public.
- **BeaverNest routed service:** continues serving the household throughout and is never touched by this work.

## Required Outcomes

- Every check `apps/badakmini-cli` performs today — word budgets, directory maps, internal Markdown links, Mermaid accessibility and legibility, and coding-harness parity — is performed by the released `rhino` binary against this repository, driven entirely by declared configuration.
- The tool contains no BeaverNest path, tree name, word limit, harness name, or capability vocabulary as a built-in default. A repository that declares nothing gets a clear configuration error, never a silent BeaverNest assumption.
- That claim is proved by adoption, not assertion: RHINO validates its own repository — no governance tree, no plans tree, an empty harness roster — before the first release is tagged and continues to do so in CI, and the schema is hardened against all four target trees before anything is published.
- The scenario corpus that specifies this behaviour lives with the tool and executes at unit, integration, and process boundaries, so every later consumer inherits a specification rather than a folk understanding.
- BeaverNest consumes the tool through a pinned bootstrap that verifies both the archive checksum and the executable's embedded release identity before running it, and fails closed when either is wrong.
- After cutover, `apps/badakmini-cli`, `apps/badakmini-cli-e2e`, and the .NET toolchain they require are gone from this repository, and no rule, document, target, hook, or specification still names them.
- grind-in-public's three `badak-mini` hygiene checks are gone from that repository, while its repository-specific Node checks and its `harness rule-change` trigger stay exactly where they are — RHINO takes over general hygiene, not another repository's own rules. Its Go toolchain stays with `rule-change`, so unlike BeaverNest that repository does not shed a runtime; what it sheds is the duplicate implementation.
- HIPPO adopts without losing anything: it has no validator to retire, and its existing gates are untouched.
- The maintainer's published RHINO artifacts cover macOS and Linux on both `amd64` and `arm64`, and a release tag is never replaced.
- The cost of the gate is measured before and after in both cutover repositories, and the change does not make it slower or heavier than what it replaced. The distribution path is measured too — what a consumer pays to get from a pinned lock line to a running check — because a cheaper gate reached through an expensive bootstrap is not cheaper.
- A repository adopting RHINO can learn it, use it, and look things up without reading its source, through the same documentation model HIPPO already proves; and RHINO's own repository passes the checks RHINO performs.

## Non-goals

- Adopting RHINO in `ose-public` or `ose-private`. Their adoption is enabled here and executed elsewhere.
- Retiring or merging `ose-public`'s existing `apps/rhino-cli`. This plan aligns with its surface so that a future merge is a configuration port; it does not perform that merge.
- Absorbing any repository-specific check that is not general repository hygiene. grind-in-public's project-contract, governance-structure, workflow-contract, and spelling checks stay in grind-in-public.
- Adding validators, output formats, or repository-hygiene concerns that Badakmini does not implement today.
- Changing any governed content in order to make it pass. The corpus that passes today must pass after cutover; a rule change is a separate, explicitly authorized decision.
- Changing BeaverNest product behaviour, storage, deployment, or routing.

## Risks and Controls

- **Silent behaviour loss during rewrite.** Five validators and roughly 5,000 lines move languages at once. Control: the same 81-scenario corpus binds at three adapter levels before cutover, and each retired binary is deleted only after the new one has passed that repository's full gate on its real corpus.
- **Word-count divergence.** The budget is a numeric gate; a different Unicode word-boundary or grapheme rule silently changes pass or fail on every governed file — 57 of them in this repository at the time of planning. Control: a direct count comparison across every governed file before the old binary is removed, retained as the single narrow numeric exception to the corpus-only proof strategy.
- **Regex dialect gap.** Badakmini's Mermaid and Markdown parsing leans on .NET regular expressions, which support constructs Rust's `regex` crate deliberately omits. Control: inventory every pattern and its required features before any port work begins; treat an unsupported construct as a design task, not an implementation surprise.
- **Unmaintained dependency.** The configuration format alignment points at YAML, and `serde_yaml` is archived. Control: settled on 2026-09-07 against primary sources — `yaml_serde`, the YAML organization's own continuation, with `noyalib` rejected on its author's withdrawn-for-unsoundness track record. Residual: its `libyaml-rs` parser is transpiled C in `unsafe` Rust, so `cargo deny check` gates advisories against it, and the evidence is re-verified at execution time rather than trusted from planning.
- **Four-repository coordination.** No repository can verify a pin that does not exist, a bad release cannot be recalled, and a tool change discovered in the third repository invalidates the first two. Control: strict ordering — upstream green, hardened against every target tree, then tag, then adopt one repository at a time with each gated on the previous — and any tool change sends the work back through the corpus and re-verifies the earlier repositories before proceeding.
- **Two cutovers in one plan.** BeaverNest and grind-in-public each retire a working validator, doubling the blast radius. Control: independent rollbacks — each restores its own deleted project and previous hook from Git, neither touches the other, and neither touches a published tag. HIPPO is sequenced between them precisely because it is additive and cannot regress anything.
- **Public repository exposure.** All four repositories are public, BeaverNest included, so nothing here is protected by obscurity and the [public repository data-safety convention](../../../repo-governance/conventions/public-repository-data-safety.md) already governs every file this plan touches. What changes is surface, not privacy class: a new public repository is created, a validator's full source moves into it, and configuration describing four real trees is published alongside. Control: apply the convention to everything moved upstream and to every `repo-config.yml`; move behaviour, never household paths, hostnames, or runtime values; and treat the new repository as governed from its first commit rather than once it has content worth protecting.
- **An unmeasured rewrite.** "Rust is faster and smaller" is an intuition, and a rewrite can quietly regress on the axis it was chosen for. Control: baselines captured before any change — necessarily so, since both retired validators cease to exist at cutover — with warm gate time and peak memory as blocking thresholds, and any regression reported as prominently as any gain.
- **Enforcement gap during transition.** A window in which neither validator gates pushes would let governed content drift. Control: the pre-push hook moves from one gate to the other inside a single change, never through an ungated intermediate state.
