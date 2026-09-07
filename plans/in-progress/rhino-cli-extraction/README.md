# RHINO CLI Extraction

**Status:** In Progress

**Created:** 2026-09-07

**Started:** 2026-09-07

**Completed:** —

**Scope:** Extract Badakmini's repository-governance validators into a standalone, configuration-driven Rust CLI released from `wahidyankf/rhino`, and make BeaverNest its first pinned consumer

## Context

[`apps/badakmini-cli`](../../../apps/badakmini-cli/README.md) is a 5,000-line F# application that enforces this repository's documentation contract: word budgets, directory maps, internal Markdown links, Mermaid accessibility, and coding-harness parity. Every one of those rules is a general repository-hygiene concern, but the implementation hard-codes BeaverNest's answers to them — the 750-word limit, the `repo-governance`/`docs`/`specs`/`plans` tree list, `.agents/` as the canonical harness root, and exactly three harnesses. Four sibling repositories (`grind-in-public`, `hippo`, `ose-public`, `ose-private`) need the same enforcement and cannot get it.

The repository already proves the alternative works. [HIPPO](../../../repo-governance/development/resource-aware-development.md) started as an in-repository `apps/resource-guard/` module set, moved to its own repository, and is now consumed here through a checksum-pinned `./hippo` bootstrap with no .NET-style toolchain cost at all. This plan applies that pattern to Badakmini.

The name is not new. `ose-public` already ships an `apps/rhino-cli` under the same acronym — **RHINO**, Repository Hygiene & INtegration Orchestrator — with an overlapping command surface and a declared `repo-config.yml` schema. That project has already travelled Go → Rust → F#. The standalone repository is intended to eventually replace it, so this plan adopts its command spelling and configuration shape by default rather than inventing a third dialect — and records each deliberate departure with its reason, of which there are two.

## Approach

Build `wahidyankf/rhino` as a generic Rust CLI that owns no repository's policy, documented the way HIPPO is documented. Every constant Badakmini hard-codes becomes a field in a `repo-config.yml` that the consuming repository owns and the tool reads. Move the existing 81-scenario Gherkin corpus into the new repository as its canonical specification and re-bind it in Rust at unit, integration, and process boundaries. Make RHINO its own first consumer before tagging anything, so a repository that is not BeaverNest has already stressed the schema by the time `v0.1.0` exists. Release it exactly as HIPPO is released — immutable tags, per-platform archives, a `checksums.txt`, and an embedded release identity — then consume it here through a pinned `./rhino` bootstrap. Retire `apps/badakmini-cli` and `apps/badakmini-cli-e2e` in the same plan, so the repository never carries two validators.

Behaviour parity is proved through the shared scenario corpus at all three adapter levels, not through a byte-for-byte differential run against the retired binary. One narrow numeric exception is retained and justified in [the cutover design](tech-docs/03-beaver-nest-cutover.md): the word budget is a counting gate over 49 governed files, so its counts are compared directly before the old binary is deleted.

The four other repositories are explicitly out of scope. Their adoption becomes possible because the tool is configuration-driven, but no work happens for them here.

## Dependencies

- A published, tagged `wahidyankf/rhino` release must exist before BeaverNest can pin it; the repository is currently an empty initial commit at [wahidyankf/rhino](https://github.com/wahidyankf/rhino).
- GitHub Actions runners for `macos` and `ubuntu` on both `amd64` and `arm64`, because Rust cannot cross-build the Darwin targets from one Linux job the way HIPPO's Go pipeline does.
- The existing `./hippo` bootstrap as the proven reference implementation for safe pinned consumption.
- `ose-public`'s `apps/rhino-cli` and `repo-config.yml` as the alignment reference for command spelling and configuration shape.

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
- [`tech-docs/`](tech-docs/README.md) — technical entry point, upstream repository design, configuration contract, and consumer cutover.
