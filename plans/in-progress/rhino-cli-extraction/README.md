# RHINO CLI Extraction

**Status:** In Progress

**Created:** 2026-09-07

**Started:** 2026-09-07

**Completed:** —

**Scope:** Extract Badakmini's repository-governance validators into a standalone, configuration-driven Rust CLI released from `wahidyankf/rhino`, and adopt it in four repositories — rhino itself, BeaverNest, HIPPO, and grind-in-public — retiring the two existing validator implementations

## Context

`apps/badakmini-cli` was a 5,000-line F# application that enforced this repository's documentation contract: word budgets, directory maps, internal Markdown links, Mermaid accessibility, and coding-harness parity. Every one of those rules is a general repository-hygiene concern, but the implementation hard-codes BeaverNest's answers to them — the 750-word limit, the `repo-governance`/`docs`/`specs`/`plans` tree list, `.agents/` as the canonical harness root, and exactly three harnesses. Sibling repositories need the same enforcement and cannot get it — so they have written their own instead. `grind-in-public` runs `badak-mini`, an independent Go implementation of the same idea, and `ose-public` runs `rhino-cli`, which has itself travelled Go to Rust to F#. The same validator has now been written three times in three languages, which is the problem stated as history rather than as prediction.

The repository already proves the alternative works. [HIPPO](../../../repo-governance/development/resource-aware-development.md) started as an in-repository `apps/resource-guard/` module set, moved to its own repository, and is now consumed here through a checksum-pinned `./hippo` bootstrap with no .NET-style toolchain cost at all. This plan applies that pattern to Badakmini.

The name is not new, and neither is the shape. `ose-public` already ships an `apps/rhino-cli` under the same acronym — **RHINO**, Repository Hygiene & INtegration Orchestrator — with an overlapping command surface and a declared `repo-config.yml` schema. That project has already travelled Go → Rust → F#. The standalone repository is intended to eventually replace it, so this plan adopts its command spelling and configuration shape by default rather than inventing a third dialect — and records each deliberate departure with its reason, of which there are two.

## Approach

Build `wahidyankf/rhino` as a generic Rust CLI that owns no repository's policy, documented the way HIPPO is documented. Every constant Badakmini hard-codes becomes a field in a `repo-config.yml` that the consuming repository owns and the tool reads. Move the existing 81-scenario Gherkin corpus into the new repository as its canonical specification and re-bind it in Rust at unit, integration, and process boundaries. Release it exactly as HIPPO is released — immutable tags, per-platform archives, a `checksums.txt`, and an embedded release identity — then consume it through a pinned `./rhino` bootstrap.

Behaviour parity is proved through the shared scenario corpus at all three adapter levels, not through a byte-for-byte differential run against the retired binary. One narrow numeric exception is retained and justified in [the cutover design](tech-docs/03-beaver-nest-cutover.md): the word budget is a counting gate, so counts are compared file by file in each cutover repository before its old binary is deleted.

Adopt it in four repositories, because a tool is only generic once more than one tree has proved it. RHINO validates itself first from a source build, then the schema is hardened against all four target trees — nothing is tagged until it has met every one of them, because a published tag is never replaced. After the release, BeaverNest cuts over, HIPPO adopts additively, and grind-in-public cuts over, retiring both existing implementations so no repository is left running two validators of one contract.

Measure it. The gate's wall-clock cost, startup, memory, and toolchain setup are recorded before any change and again after each cutover, and the distribution path is measured end to end — what a consumer pays to go from a pinned lock line to a running check, not just how large the artifact is. The claim that this is cheaper becomes a number rather than an intuition, and a metric that got worse is reported as prominently as one that improved.

`ose-public` and `ose-private` remain out of scope. Their adoption becomes possible because the tool is configuration-driven, and `ose-public` additionally needs a merge decision about its own `rhino-cli` that this plan deliberately does not make.

## Dependencies

- A published, tagged `wahidyankf/rhino` release must exist before any repository can pin it; the repository is currently an empty initial commit at [wahidyankf/rhino](https://github.com/wahidyankf/rhino).
- GitHub Actions runners for `macos` and `ubuntu` on both `amd64` and `arm64`, because Rust cannot cross-build the Darwin targets from one Linux job the way HIPPO's Go pipeline does.
- The existing `./hippo` bootstrap as the proven reference implementation for safe pinned consumption.
- `ose-public`'s `apps/rhino-cli` and `repo-config.yml` as the alignment reference for command spelling and configuration shape.
- Local checkouts of `hippo` and `grind-in-public`, and authorization to commit in each, since both are separate repositories with their own history.
- grind-in-public's `badak-mini` hygiene checks as the second retirement target, with its Node-script repository checks and its `harness rule-change` trigger explicitly staying where they are.

## Navigation

- [Business requirements](brd.md)
- [Product requirements](prd.md)
- [Technical design](tech-docs/README.md)
- [Delivery checklist](delivery.md)
- [Learnings](learnings.md)

## Directory Map

- [`brd.md`](brd.md) — goal, roles, required outcomes, non-goals, and risk controls.
- [`delivery.md`](delivery.md) — ordered tasks, red-green-refactor cycles, and blocking checkpoints.
- [`learnings.md`](learnings.md) — dated evidence and decisions captured during delivery.
- [`prd.md`](prd.md) — maintainer stories and executable acceptance criteria.
- [`tech-docs/`](tech-docs/README.md) — technical entry point, upstream repository design, configuration contract, this repository's cutover, the sibling consumers, and the benchmarks.
