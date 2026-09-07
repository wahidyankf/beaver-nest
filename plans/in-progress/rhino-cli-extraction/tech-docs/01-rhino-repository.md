# Upstream Repository Design

`wahidyankf/rhino` is a standalone Rust CLI. It is generic by construction: it holds no repository's policy, no default tree list, no default word limit, and no default harness roster. Its contributor rules mirror HIPPO's first rule — keep the CLI repository-independent and add no product-specific defaults.

## Repository Shape

The layout is idiomatic Rust, not a transliteration of HIPPO's Go layout. The split is deliberate: **mechanisms are Rust's; principles are this repository's.** Where a Rust convention exists for where code lives and how it is built, it wins. What must be proved before a change is accepted — that is BeaverNest's engineering principle set, and it travels because it is a property of how the maintainer works, not of F#. What does not travel is BeaverNest's _implementation_ of those principles: its target names, its directory names, its runner, and its Nx wiring are all local answers, and upstream is free to give Rust-native answers to the same questions.

```text
rhino/
  Cargo.toml           package "rhino" + [workspace] members = ["xtask"]
  Cargo.lock           committed; a binary crate pins its whole graph
  rust-toolchain.toml   exact toolchain, so CI and contributors agree
  rustfmt.toml          formatting is settled in the file, not in review
  clippy.toml           lint thresholds
  deny.toml             cargo-deny: advisories, licences, duplicate graph
  .cargo/config.toml    alias xtask = "run --package xtask --"
  hippo, hippo.lock     pinned guard for local heavy cargo work
  .husky/               pre-commit, commit-msg, pre-push
  package.json          contributor-only tooling; no runtime dependency
  lint-staged.config.mjs, commitlint.config.cjs, .prettierignore
  src/
    lib.rs             the library; every module below is reachable from it
    main.rs            argument dispatch to exit code, and nothing else
    ...
  tests/               unit/, integration/, e2e/, coverage/, shared support/
  xtask/               release and packaging automation, written in Rust
  specs/               canonical architecture and behaviour corpus
  docs/                Diataxis: tutorials, how-to, reference, explanation
  repo-config.yml      RHINO's policy for RHINO; it validates itself
  .github/workflows/   ci.yml, scheduled.yml, release.yml
  AGENTS.md, CLAUDE.md, README.md, CHANGELOG.md, LICENSE
```

Four choices are load-bearing.

**Library plus binary, not a binary alone.** `src/lib.rs` exists because Rust's `tests/` directory compiles each file as a separate crate that can only link against the _library_ target. A bin-only crate would force every integration and behaviour test into `#[cfg(test)]` modules inside `src/`, which is exactly the arrangement this project cannot have: the corpus must execute against the public API at a real boundary. `main.rs` therefore holds only argument dispatch and exit-code mapping. `#![forbid(unsafe_code)]` sits at the top of `lib.rs`, making the no-`unsafe` claim a compiler guarantee for RHINO's own code rather than a review convention. It does not extend to dependencies; see the YAML section for the one place that distinction matters.

**`xtask`, not a shell script.** HIPPO builds releases through `scripts/build-release.sh` because Go's toolchain and shell are its native pair. Rust's equivalent convention is `cargo-xtask`: automation written as a workspace member and invoked as `cargo xtask dist`, so the release pipeline is type-checked, unit-testable, cross-platform without shell quoting, and shares the crate's own version and metadata rather than duplicating them in a script. A single `xtask` member is also why the root package declares a workspace at all.

**Modules as files, not `mod.rs` directories.** `src/markdown.rs` with `src/markdown/internal_link.rs` beside it, following the 2018-edition path convention. `mod.rs` is legacy style and makes every open editor tab read `mod.rs`.

**`specs/` at the root, which is not a Rust convention.** The behaviour corpus is Gherkin and the architecture model is C4; neither is Rust source, and both are shared with the consuming repositories' own specification trees. Putting them under `tests/` would bury a specification inside an implementation detail. This one is a deliberate departure and is called out in `AGENTS.md` so it is not "corrected" later.

There is no `crates/` directory, because there is one library and one binary and a virtual workspace would add a directory level that buys nothing. Nx is absent, as it is in HIPPO: `cargo` is the task runner, and `npm` exists only for `husky`, `commitlint`, and `lint-staged`.

## Crate Structure

One crate, one binary named `rhino`. The module boundaries mirror Badakmini's file boundaries so that the port is reviewable side by side rather than as a redesign.

| Module       | Ports from                               | Responsibility                                                                                                                                                             |
| ------------ | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `runtime`    | `Runtime.fs`                             | The filesystem and output ports. A trait, so unit tests substitute an in-memory tree and captured writers, exactly as the F# record of functions does today.               |
| `config`     | _(new)_                                  | Locates, parses, and validates `repo-config.yml`; rejects unknown keys; fails closed. Owns the whole schema in [the configuration contract](02-configuration-contract.md). |
| `markdown`   | `Governance.fs` (link and Mermaid parts) | Markdown scanning, internal-link resolution, Mermaid block extraction, `classDef` colour checks, and grapheme-counted label legibility.                                    |
| `governance` | `Governance.fs` (budget and map parts)   | Unicode word counting, per-surface budget evaluation, README presence, and direct-sibling directory-map completeness.                                                      |
| `harness`    | `HarnessContract.fs`                     | Canonical rule, skill-bundle, agent-prompt, and capability record construction; adapter discovery; SHA-256 digest comparison; semantic permission comparison.              |
| `cli`        | `Cli.fs`                                 | The command tree, global flags, output rendering, and exit-code mapping.                                                                                                   |

`Program.fs`'s job becomes `main.rs`: parse, dispatch, map the result to an exit code.

## Design Philosophy

RHINO is a Unix tool. That is a constraint on its design, not a description of its host operating system, and it is what keeps a five-validator binary from becoming a framework.

**One job per leaf.** The binary is a toolbox in the `git` and `busybox` sense: a dispatcher over small independent tools. `md internal-link validate` knows nothing about word budgets; `governance word-budget validate` knows nothing about Mermaid. They share a filesystem port and a finding type, and nothing else. No leaf calls another. There is deliberately no aggregate `validate-everything` command — composing the leaves is the caller's job, which is exactly what the consumer's `test:repo` target does today by running eight invocations in parallel.

**Do one thing well, and nothing else.** RHINO reads. It never writes to the repository it inspects, never opens a socket — not even loopback — never spawns a child process, and never resolves a path outside the root it was given. Each of those is enforced by a policy test, not just intended. A tool that only reads is a tool a maintainer can run without thinking about it.

**Text in, text out.** Findings go to stdout, diagnostics to stderr, so `rhino md internal-link validate | grep` works and the diagnostics do not pollute the pipe. `--output json` makes the same findings machine-readable for a harness. Exit status is the primary result: `0` clean, `1` findings, `2` the tool could not do its job. A caller that only checks the exit code gets a complete answer.

**Quiet when there is nothing to say.** `--quiet` suppresses summary output so a clean run prints nothing at all, matching HIPPO's "invisible when healthy" behaviour and `ose-public`'s existing global flag. It is a flag rather than the default because the current `test:repo` output is prefixed per-validator summaries that a maintainer reads, and silently removing them would be a behaviour change nobody asked for.

**Compose with the tools that already exist.** `--file` may be repeated to inspect a caller-selected set instead of scanning, and accepts `-` to read newline-delimited paths from stdin. That makes `git diff --name-only | rhino md mermaid validate --file -` the natural changed-files check, which is the shape the Badakmini workflow already recommends by hand.

**No state, no daemon, no configuration of its own.** One short-lived process per invocation. RHINO's only configuration is the consuming repository's file, which RHINO does not own and never writes.

## Command Contract

Noun groups with a final verb, which is already how both Badakmini and `ose-public`'s `rhino-cli` are spelled.

```text
rhino governance word-budget validate      [--root <path>]
rhino governance directory-map validate    [--root <path>] [--directory <path>]
rhino governance harness-contract validate [--root <path>]
rhino md internal-link validate            [--root <path>]
rhino md mermaid validate                  [--root <path>] [--file <path>|-]...
rhino md word-count inspect --file <path>  [--root <path>]
rhino repo-config validate                 [--root <path>]
rhino version                              [--json]
```

Two deliberate alignments with `ose-public`, and two deliberate divergences:

- `--format text|json` becomes `--output text|json`, matching `ose-public`'s global flag name. `markdown` output is not implemented; the flag rejects it rather than silently accepting it.
- `repo-config validate` is added, matching `ose-public`'s command of the same name, so a configuration error is diagnosable without running a validator.
- `links` becomes `internal-link`. Both Badakmini and `ose-public` spell this leaf `md links validate`, and both are imprecise: the validator resolves _local document targets_ and never fetches, resolves, or reports on an external URL. A maintainer reading `md links validate` in a gate log has every reason to think external links are covered. `md internal-link validate` names what the tool actually promises, which matters more here than matching a spelling that a future merge can adopt in one rename. Recorded as a divergence so the alignment claim stays honest.
- `--quiet` and `--verbose` are adopted from `ose-public`'s global flag set. `--no-color` is adopted as well; colour is disabled automatically when stdout is not a terminal, so the flag is only needed to force it off on one.
- `--root` is retained even though `ose-public`'s in-repository binary does not need it. A released binary executes from a cache directory, so the repository under inspection must be nameable. It defaults to the current directory.

`rhino version --json` must emit exactly `{"schemaVersion":1,"version":"vX.Y.Z","commit":"<40 hex>"}`. The consumer bootstrap compares that string to the identity it builds from the lock, so its field order and spacing are part of the release contract, not a formatting detail.

Exit codes stay Badakmini's: `0` success or help, `1` findings, `2` invalid invocation, invalid root, unreadable or invalid configuration, or execution error. HIPPO's `73`, `75`, and `78` are process-guard outcomes and have no meaning for a read-only validator; adopting them would make two tools in one repository disagree about what a number means.

## Dependency Decisions

Each entry below must satisfy [dependency selection](../../../../repo-governance/development/dependency-selection.md): a concrete need the standard library cannot meet reasonably, established community practice, and current primary-source evidence of maintenance. The first four are settled; the last two are recorded as open decisions with an owning delivery task, because asserting their maintenance status without checking it is exactly what the convention forbids.

| Need                                             | Candidate                                      | Standing                                                                                                                                                                                                                                                                                                                             |
| ------------------------------------------------ | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Argument parsing with subcommand groups          | `clap` (derive)                                | Settled. Rust has no standard argument parser; `clap` is the ecosystem default and matches the declarative style `Argu` gives `ose-public`.                                                                                                                                                                                          |
| JSON output                                      | `serde` + `serde_json`                         | Settled. The `--output json` boundary is a public contract and hand-rolled serialization would be a defect source.                                                                                                                                                                                                                   |
| SHA-256 for harness digests                      | `sha2`                                         | Settled. No standard-library hashing. Digests are internal to a single run, so no cross-version stability constraint applies.                                                                                                                                                                                                        |
| Grapheme-cluster counting                        | `unicode-segmentation`                         | Settled. The Mermaid legibility rule counts user-perceived characters; this crate implements UAX #29, which is the same standard .NET's text-element enumeration follows. Parity on emoji and ZWJ sequences is a named verification item, not an assumption.                                                                         |
| Regular expressions                              | `regex`                                        | **Open.** Rust's `regex` has no lookaround and no backreferences by design. Badakmini's Markdown, `classDef`, node-label, state-node, and edge-label patterns must be inventoried first. Any pattern that needs an omitted construct is rewritten as explicit parsing, not worked around with a heavier engine.                      |
| YAML parsing                                     | `yaml_serde`                                   | Settled on evidence, 2026-09-07. dtolnay archived `serde_yaml`; `yaml_serde` is the YAML organization's own continuation of it, maintained by Ingy döt Net and others. Active as of this date, no advisory, and its adoption is real rather than nominal. See the YAML section below for the evidence and the rejected alternatives. |
| TOML and JSON-with-comments for harness adapters | `toml`, plus the existing owned JSONC handling | Settled. Codex agent adapters are TOML and OpenCode configuration is JSON or JSONC; Badakmini already parses only owned subsets of both, and that narrowness carries over.                                                                                                                                                           |
| Gherkin execution                                | `cucumber`                                     | Settled. The corpus is the specification and must execute; Rust has one established Gherkin runner.                                                                                                                                                                                                                                  |

Development tooling: `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo llvm-cov` for the coverage gate, and `cargo deny check` for advisories, licences, and duplicate-graph drift — which is how [dependency selection](../../../../repo-governance/development/dependency-selection.md)'s requirement that dependencies enter the existing security and licence checks is actually met.

## The YAML Dependency

This one is called out separately because it is the only dependency where the obvious choice is archived and the replacement field contains a trap.

`serde_yaml` was archived by its author in March 2024. Four candidates replace it, and they are not equivalent:

| Candidate                                   | Disposition                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `yaml_serde` (`github.com/yaml/yaml-serde`) | **Selected.** The YAML organization's own continuation of `serde_yaml`, with full API compatibility. Repository created 2025-11-25, last push 2026-08-18, `0.10.7` published 2026-08-18, seven releases in 2026, several distinct human maintainers including Ingy döt Net — a YAML co-author and the maintainer of libyaml and PyYAML — plus active Dependabot. 1.96M total and 1.63M recent downloads. No OSV or RustSec advisory. Recent commits are real maintenance: an IO-error-source fix, MSRV 1.82 preservation, `no_std` work.                                                                                                                                                                                                                              |
| `noyalib`                                   | **Rejected**, and worth stating why. It advertises exactly what this project wants — pure Rust, zero `unsafe`, serde integration — but it is published by the author of `serde_yml` and `libyml`, the two crates that earned RUSTSEC-2025-0068 and RUSTSEC-2025-0067 for unsoundness and were then archived. It sits at `0.0.39` with ten releases in the six days before this decision. On the [dependency-selection](../../../../repo-governance/development/dependency-selection.md) test of "a credible response path for defects and security issues", a maintainer whose two previous crates in this exact problem space were withdrawn for unsoundness is the evidence, and it points the wrong way. Revisit only if it matures under different circumstances. |
| `serde_norway`, `serde_yaml_ng`             | Viable community forks, but neither carries the upstream organization's ownership. Held as fallbacks if `yaml_serde` stalls.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `serde_yml`                                 | **Disqualified.** RUSTSEC-2025-0068, unsound and archived.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |

One honest caveat. `yaml_serde` depends on `libyaml-rs`, which is libyaml transpiled from C by `c2rust` — roughly 11,000 lines of `unsafe` Rust, published 2026-03-11 with no release since. `#![forbid(unsafe_code)]` in RHINO's own crate constrains RHINO's code and says nothing about that dependency. This is the same parser lineage `serde_yaml` always used, it is the most-exercised YAML path in the ecosystem, and no advisory stands against it — but it is `unsafe` code in the dependency graph, not a pure-Rust parser, and the plan should not imply otherwise. `cargo deny check` in CI is what turns a future advisory against it into a build failure rather than a surprise.

Because maintenance status decays, the delivery checklist re-verifies this evidence at execution time rather than trusting a planning-time snapshot.

## Binary Size

A small executable is the reason Rust was chosen, so it is treated as a release requirement with a measured budget rather than a hoped-for side effect. Five repositories will each cache one archive per platform they run on.

The release profile sets `opt-level = "z"`, `lto = "fat"`, `codegen-units = 1`, `panic = "abort"`, and `strip = "symbols"`. `cargo xtask dist` records the stripped size of each of the four executables, and the artifact-verification suite fails the release if any of them exceeds a declared ceiling. The ceiling is set from the first real measurement in delivery and then held; a later increase is a deliberate, recorded decision, not a drift.

Two dependency choices pull against this and are the first places to look if the budget is tight. `regex` compiles a substantial Unicode tables payload, and `clap`'s derive feature generates more code than its builder API. Neither is removed speculatively — the budget is measured first, and only a measured overrun justifies trading ergonomics for bytes. If it comes to that, the ordered options are: narrow `regex`'s default features, replace the simplest patterns with explicit parsing, then move `clap` to its builder API.

## Specification Corpus

The seven `.feature` files and 81 scenarios move from `specs/apps/badakmini/cli/behaviours/` to `specs/behaviours/`, and `architecture.md` moves to `specs/architecture.md` rewritten for the Rust containers and the new configuration boundary.

The move is not a copy. Scenarios currently assert BeaverNest's constants directly — the number 750, the tree name `repo-governance`, the paths `.claude` and `.agents`. In a generic tool those are inputs, so each such scenario is reworded to establish its policy in a `Given` and assert against it. That rewrite is the single largest source of semantic risk in the port and is why it happens before any Rust validator code is written, with the resulting corpus reviewed under the [Gherkin implementation review](../../../../repo-governance/workflows/gherkin-implementation-review.md).

One TickSpec-specific workaround does not travel: the `{hash}` placeholder that exists because TickSpec treats every literal `#` as a comment. Where `cucumber` parses `#` inside a table cell or DocString correctly, the literal returns and the binding drops the expansion.

## Testing Principles and Their Rust Expression

The principles below come from this repository's [quality-gate standard](../../../../repo-governance/development/quality-gates.md), [BDD standard](../../../../repo-governance/development/behaviour-driven-development.md), [specification maintenance](../../../../repo-governance/development/specification-maintenance.md), and [test-driven development](../../../../repo-governance/development/test-driven-development.md). They are restated in RHINO's own `AGENTS.md` as upstream rules, so the public repository is self-governing rather than dependent on a private one it cannot read. Rust supplies the mechanism; the boundaries are BeaverNest's, unchanged.

### The three boundaries

BeaverNest defines these once, and RHINO inherits the definitions rather than paraphrasing them:

| Layer           | May touch                                                                                                                                                             | May not touch                                                                                                             | RHINO's adapter                                                                                      |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| **Unit**        | Nothing real. Filesystem, environment, clock, randomness, child processes, and network are all injected fakes — in setup _and_ in assertions.                         | Any real OS resource.                                                                                                     | The `RepositoryFileSystem` trait backed by an in-memory tree, with captured output writers.          |
| **Integration** | Real local OS resources and same-machine processes: isolated files, environment state, child processes, and the standard streams. May bind a loopback socket it owns. | External network, a browser, or the routed public origin. Every resource is isolated and deterministically cleaned.       | Real temporary directories containing a synthetic repository, validated through the library API.     |
| **End-to-end**  | A public system boundary, plus OS resources, processes, and network where the journey needs them.                                                                     | Production users or data — the [test-data iron rule](../../../../repo-governance/development/test-identities.md) applies. | The built `rhino` executable, observed only through argv in and stdout, stderr, and exit status out. |

Two rules from that standard decide every borderline case, and both are easy to get wrong for a CLI:

**Classify by the strongest real boundary touched by setup, subject, _or_ assertions.** A test whose assertion reads a real file is an integration test even if its subject is pure.

**End-to-end is defined by public-boundary _observation_, not by permission to use more resources.** Spawning a child process does not make a test end-to-end — integration is explicitly allowed to do that. What makes RHINO's E2E adapter E2E is that it observes _only_ the process contract a consumer can see, and never reaches into the library behind it.

### Layout

BeaverNest requires executable tests in separate `unit`, `integration`, and E2E directories, while shared contracts, bindings, fixtures, and non-executable support may stay shared. Cargo compiles `tests/<name>/main.rs` as one test target, so the directory separation and the Rust convention are the same arrangement:

```text
tests/
  unit/main.rs          every scenario, in-memory filesystem, captured output
  integration/main.rs   every applicable scenario, real isolated temp trees
  e2e/main.rs           every applicable scenario, built binary, public contract only
  coverage/main.rs      static corpus and binding check; runs no scenario
  support/              shared steps and vocabulary; no main.rs, so not a target
```

`tests/support/` is deliberately not a test target: it is the shared, non-executable support the standard permits, ported from `BehaviourSteps.fs` and `BehaviourSupport.fs`.

### One product invariant that is stricter than its layer

The integration layer _permits_ a test to bind a loopback socket it owns. RHINO's integration adapter forbids even that, and so does every other layer, because RHINO is a network-free tool by design. BeaverNest's Badakmini README already draws this distinction explicitly, and it must survive the port: **this is a product invariant, not an instance of the integration-layer boundary.** Someone reading the policy test later must not "relax" it back to the layer rule on the grounds that loopback is allowed — the layer allows it, and RHINO still does not.

The same policy tests cover no child process, no write to the inspected tree, and no path escaping the declared root, alongside `#![forbid(unsafe_code)]` in the crate itself.

### Gate composition

| Principle                                                                                                                         | RHINO's expression                                                                                                       |
| --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| The specification is executable and written before the behaviour exists.                                                          | Gherkin under `specs/behaviours/`, run by the `cucumber` crate.                                                          |
| One corpus; only the driver changes between layers.                                                                               | Three targets over `specs/behaviours/`, sharing `tests/support/`.                                                        |
| Unit runs every scenario and is never exempt.                                                                                     | `tests/unit/` enumerates the whole corpus.                                                                               |
| An outer-layer exemption names its exact boundary and alternative proof, and never cites difficulty, runtime, flakiness, or cost. | `@integration-exempt` / `@e2e-exempt` with the required preceding comment line, validated statically.                    |
| A binding must establish, invoke, and observe. Matching the step text is not enough.                                              | `tests/coverage/` rejects placeholders, no-ops, unused bindings, and ambiguity, and executes no scenario.                |
| Unit is the only numeric gate; excluded modules are named in the project README.                                                  | `cargo llvm-cov` at 99% or above, with `main.rs` and the concrete filesystem adapter named as exclusions in `README.md`. |
| Integration carries no coverage threshold.                                                                                        | None applied.                                                                                                            |
| **The quick gate never runs integration or E2E scenarios.**                                                                       | Format, clippy, `cargo deny`, unit, coverage floor, static behaviour check, and self-validation — and nothing else.      |
| Scheduled CI runs every integration suite, then the complete unfiltered E2E target.                                               | A scheduled workflow, which is where BeaverNest's retiring `badakmini-test-symphony` job lands.                          |
| A stated architectural boundary is enforced by a test.                                                                            | The policy tests above.                                                                                                  |
| Behaviour change is Gherkin, then a proved-red binding, then code.                                                                | `cargo test` failing for the named reason before implementation, recorded per cycle in `delivery.md`.                    |

That table contains one correction to an earlier draft of this plan. HIPPO's `test-quick.sh` runs all three behaviour adapters in its pre-push gate, and copying it would have put integration and E2E scenarios inside RHINO's quick gate — which BeaverNest's standard forbids outright, in both `test:quick` and Git hooks. HIPPO is a single self-hosting module with no scheduled-gate split; RHINO follows BeaverNest here, and the two slow adapters move to the scheduled workflow.

## RHINO Is Its Own First Consumer

RHINO adopts RHINO before BeaverNest does. The upstream repository ships its own `repo-config.yml`, and CI runs the freshly built binary against its own tree on every push.

The reason is not tidiness. A tool extracted from one repository will carry that repository's assumptions in places nobody predicted, and the corpus cannot find them — scenarios are written by the same person holding the same assumptions. A second real repository can, and RHINO's own tree is the cheapest one available and the most usefully different:

| BeaverNest has                                                               | RHINO has                                                | What that exercises                                                                            |
| ---------------------------------------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `repo-governance/`, `docs/`, `specs/`, `plans/`                              | `docs/`, `specs/`                                        | Mapped trees are genuinely a list, not four names with a loop around them.                     |
| A 750-word budget over `AGENTS.md` and a governance tree                     | A budget over `AGENTS.md` and `README.md`                | Surface globs select real files in a tree shaped nothing like the first.                       |
| Three harnesses, `.agents/` canonical roots, skill bundles, command wrappers | `AGENTS.md` and `CLAUDE.md`, and an empty harness roster | The degenerate case. A roster of zero must be a legal declaration, not a crash and not a skip. |
| Nx, `.NET`, Elixir, an Nx target graph                                       | `cargo` and nothing else                                 | Scan exclusions are declared, not a hardcoded list of BeaverNest's build directories.          |

The empty-roster row is the one that repays the effort immediately. It forces an answer to a question the schema would otherwise defer: an omitted section is a configuration error, and a genuinely empty roster is declared explicitly as empty. Fail-closed either way, but the two are not the same, and discovering that against a real repository in Phase 4 is far cheaper than discovering it in a sibling repository after `v0.1.0` is pinned.

Ordering matters as much as the act. Self-adoption sits before the release tag, so what ships as `v0.1.0` has already survived a repository that is not BeaverNest. Anything found afterwards would need a second tag, since a published tag is never replaced.

The ongoing cost is one configuration file and one CI step. The ongoing return is a second corpus exercising the real binary on every push, and the plain credibility of a repository-hygiene tool whose own repository passes its checks.

## Documentation

HIPPO's documentation model is adopted wholesale, because it is the same maintainer's answer to the same problem — a standalone tool consumed by repositories that did not write it — and it is demonstrably working. What follows is that model, with RHINO's pages substituted.

### Structure

`README.md` is the front door and stays around 1,400 words. Its section order is HIPPO's: title and expanded acronym, badges, a one-line `console` demo, then Highlights, Why, Install, Quick start, How it works, Documentation, Project status, the Open Sharia Enterprise family note, Development, and License. The emoji-prefixed headings are part of the house style, not decoration to be dropped.

`docs/` follows [Diátaxis](https://diataxis.fr/) with exactly four categories, and a page belongs to exactly one of them. `docs/README.md` opens with "Start here", then the "Find the right kind of help" table mapping each category to the question it answers, then a "short version" of what the tool is and is not, then the pointer to `specs/` as canonical.

Every category README carries the same four parts: a one-sentence statement of what the category is for, a redirect to the sibling category that suits a different question, the page list with an em-dash one-line summary each, and a "Next steps" block linking the other categories. `how-to/` groups its pages by verb rather than listing them flat.

### Proposed pages

| Category       | Pages                                                                                                                                                                                                                  |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tutorials/`   | Validate your first repository (about five minutes, ending in a real finding). Adopt RHINO in a second repository (about ten minutes, showing that only `repo-config.yml` differs).                                    |
| `how-to/`      | _Set up:_ install a pinned release; write `repo-config.yml`. _Integrate:_ run RHINO from a Git hook or CI; check only changed files. _Operate:_ read and fix each finding kind. _Extend:_ add a fourth coding harness. |
| `reference/`   | Command-line interface; exit codes; the `repo-config.yml` schema; finding kinds; JSON output schemas.                                                                                                                  |
| `explanation/` | Why RHINO exists; why policy lives in the consumer and not the tool; why it validates internal links only; why it never writes to the repository it inspects.                                                          |

The third explanation page is the standing answer to the `md internal-link validate` rename, so the reasoning outlives this plan.

### Authority and truth

Two rules from HIPPO's `AGENTS.md` carry over unchanged, and they are the ones that keep documentation honest:

- **`specs/` is canonical; `docs/` must not contradict it.** `docs/README.md` and `reference/README.md` both say so explicitly, in HIPPO's own words: where the documentation and the Gherkin corpus disagree about observable behaviour, the corpus wins, and the disagreement is a bug worth reporting.
- **Never publish a command or transcript that has not been executed against the current build.** Where a path cannot be exercised safely, say so rather than inventing output. Reference pages state their provenance the way HIPPO's CLI reference does — generated from the binary's own help, with the reader told to run `--help` to confirm against their installed version.

### Page craft

Tutorials are written in the first person plural, open with a time estimate and a "Before we start" list, use numbered `## Step N:` headings, show real `console` transcripts, and tell the reader plainly when their own numbers will differ. How-to pages are titled "How to <goal>", lead with a decision table, link to the reference page for exact definitions, and name the anti-pattern explicitly — HIPPO's exit-code guide says "never respond by bypassing the guard", and RHINO's equivalent says never respond to a finding by editing the governed content to satisfy the checker. Reference pages are tables of flags, defaults, and meanings plus real transcripts, with the command tree in a `text` fence. Explanation pages are for reading, not following.

Prose wraps at about 100 columns; Prettier formats Markdown through `lint-staged`, as it does in HIPPO.

### CHANGELOG

Keep-a-Changelog headings (`## [v0.1.0] — YYYY-MM-DD` with `### Added` / `### Changed` / `### Fixed`), Semantic Versioning, link definitions at the foot, and the immutability statement in the preamble — a published release is never rebuilt or replaced, which is the same rule the release pipeline enforces. Entries describe behaviour a consumer would notice, not commits.

## Contributor Rules

`AGENTS.md` upstream carries, at minimum: keep the CLI generic and repository-independent; preserve the exit-code contract and the `version --json` envelope unless the owner authorizes a breaking transition; assess `specs/behaviours/` and `specs/architecture.md` before every change; keep `README.md`, `docs/`, and `CHANGELOG.md` true to the shipped binary, with `docs/` following Diátaxis and a page belonging to exactly one category; never publish a command or transcript not executed against the current build, and say so rather than inventing output where a path cannot be exercised safely; run every scenario through the unit adapter and never add a unit exemption; build release assets only through `cargo xtask dist`; and never replace a tag or weaken checksum verification. Root `CLAUDE.md` contains only the import, matching this repository's instruction boundary.
