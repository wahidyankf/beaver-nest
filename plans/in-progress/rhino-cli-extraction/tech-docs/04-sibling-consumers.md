# Sibling Consumers: HIPPO and grind-in-public

BeaverNest is not the only repository that needs this. Two siblings adopt RHINO in the same plan, and they are deliberately different from BeaverNest and from each other — that difference is what turns "the tool is generic" from a claim into a demonstration.

## What the Survey Found

Two facts changed this plan's shape, and both were discovered rather than assumed.

**grind-in-public already runs its own Badakmini, written in Go.** `apps/badakmini-cli` there is `badak-mini`, an independent Go implementation of the same idea — not a copy of BeaverNest's F# source. Its own README says the name means "rhinoceros" in Indonesian and that its command grammar "follows the relevant slice of `rhino-cli` without porting Rhino's broader repository-management surface."

So the same maintainer has now written this validator three times — `rhino-cli` in `ose-public` (Go, then Rust, now F#), Badakmini in BeaverNest (F#), and `badak-mini` in grind-in-public (Go). That is the argument for extraction stated as history rather than as prediction, and it means grind-in-public's adoption is a second retirement cutover rather than the additive install HIPPO needs.

**HIPPO has no `CLAUDE.md` and no harness adapter directories at all.** It reaches a degenerate case that RHINO's own tree does not: not merely an empty harness roster, but the absence of the instruction adapter itself.

## The Four Trees

|                     | Instruction | Adapter     | Harness roster | Mapped trees                                | Mermaid                  | Existing validator |
| ------------------- | ----------- | ----------- | -------------- | ------------------------------------------- | ------------------------ | ------------------ |
| **rhino**           | `AGENTS.md` | `CLAUDE.md` | empty          | `docs`, `specs`                             | Mermaid C4               | none               |
| **hippo**           | `AGENTS.md` | **absent**  | empty          | `docs`, `specs`                             | ASCII art; zero diagrams | none               |
| **grind-in-public** | `AGENTS.md` | `CLAUDE.md` | three          | `repo-governance`, `docs`, `specs`, `plans` | ASCII art; zero diagrams | `badak-mini` (Go)  |
| **beaver-nest**     | `AGENTS.md` | `CLAUDE.md` | three          | `repo-governance`, `docs`, `specs`, `plans` | Mermaid; 33 diagrams     | Badakmini (F#)     |

Each row forces something the others do not:

- **HIPPO's absent adapter** makes `instruction-adapter` optional in the schema. When it is absent, the canonical instruction file must still be the only always-on instruction source — the prohibition does not weaken just because there is nothing to route.
- **grind-in-public and HIPPO use ASCII art rather than Mermaid**, so both contain zero diagrams. This is the most interesting row, and it is easy to mistake for an absence. It is a _policy difference_: BeaverNest's visualization convention mandates Mermaid and gets 33 diagrams checked; grind-in-public's does not, and gets zero. RHINO must report that zero explicitly and exit clean — never warn, never treat it as a repository defect, and never let it be indistinguishable from a directory walk that silently failed. A repository whose visualization convention is not Mermaid is a first-class consumer, not a degraded one.
- **grind-in-public's `plans/backlog` against BeaverNest's `plans/backlogs`** proves mapped trees are a declared list rather than four hardcoded names with a loop around them. Two repositories, one letter apart, and the tool must not care.
- **grind-in-public's `AGENTS.md` at exactly 749 words** against a 750-word limit is a boundary case worth keeping: it must pass, and it must pass under the same Unicode counting rule BeaverNest uses.

## Three Command Dialects, One Surface

The three existing implementations do not agree on spelling:

| Concern        | `ose-public` `rhino-cli`          | BeaverNest Badakmini                   | grind-in-public `badak-mini`         |
| -------------- | --------------------------------- | -------------------------------------- | ------------------------------------ |
| Word budget    | `governance word-budget validate` | `governance word-budget validate`      | `harness instruction-size validate`  |
| Internal links | `md links validate`               | `md links validate`                    | `harness markdown-links validate`    |
| Harness parity | —                                 | `governance harness-contract validate` | `harness capability-parity validate` |
| Mermaid        | —                                 | `md mermaid validate`                  | —                                    |

Two of the three already agree, and grind-in-public's own README states it is tracking `rhino-cli`. So the unified surface is largely the `governance` / `md` grammar this plan already adopted, with one namespace taken from grind-in-public instead, and both cutovers include renaming their invocations. No new dialect is invented; two are retired into one.

`badak-mini`'s `harness` noun group is the interesting disagreement, and it is half right. Grouping _everything_ by who consumes the rule is wrong: a word budget and a link check are about documents, not about harnesses, and `governance` / `md` groups them by subject matter — which is what a reader of `--help` is looking for, and what two of three implementations already use. But parity genuinely is about harnesses. So the unified surface keeps `governance` and `md` for documentation hygiene and adopts a top-level `harness` for parity, spelled `harness parity validate`. BeaverNest's `governance harness-contract validate` moves; grind-in-public's `harness capability-parity validate` shortens. Each dialect gives up something, and the one place `badak-mini` grouped better than Badakmini is the one place its grouping is kept.

## What RHINO Does Not Take Over

grind-in-public's repository gate runs more than `badak-mini`. It also runs Node scripts for a project contract, a governance-structure check, and a workflow contract, plus a British-spelling check and its own HIPPO bootstrap suite. **None of those move.** They are grind-in-public's repository-specific rules, not general repository hygiene, and pulling them into a tool shared by four repositories is exactly the mistake this plan exists to correct in the other direction.

The retirement there is precise: `badak-mini`'s three hygiene commands are replaced; everything else in that gate stays where it is and keeps running. That includes a fourth command inside the same binary. `badak-mini harness rule-change validate` and its `hook` form read staged paths and harness pre-edit payloads on stdin, and trigger that repository's own rules-propagation and harness-alignment workflows by name. It is not general repository hygiene, it reaches Git state and standard input, and RHINO's read-only, process-free, network-free posture excludes it by design. So it stays — and because it lives in `internal/rulechange/` inside the same Go module as `internal/governance/`, `internal/markdownlinks/`, and `internal/parity/`, the module stays with it.

## Adoption Shapes

**HIPPO — additive.** It has no validator to retire, so adoption is `./rhino`, `rhino.lock`, `repo-config.yml`, a CI step, and pre-push wiring. Nothing is removed, nothing is at risk, and its existing gates are untouched. HIPPO's contributor rules require documentation to stay true to the shipped binary and `docs/` to follow Diátaxis; RHINO now checks mechanically what that rule states in prose.

**grind-in-public — partial cutover.** The same shape as BeaverNest's up to a point: adopt, reconcile findings against the current clean result, verify with a fresh process and the retired checks removed, repoint its Nx targets and hooks, and propagate the rule change through its own governance tree. It differs at the retirement itself, and the difference is not cosmetic. BeaverNest's Badakmini is entirely hygiene, so deleting it removes .NET from that repository outright. grind-in-public's binary is not: `rule-change` shares its module, so what leaves is three packages, three commands, their bindings, and their scenarios — not the module, not `go.mod`, and not the Go toolchain. The plan previously claimed otherwise, and the claim was wrong rather than merely optimistic: it would have deleted a working pre-commit trigger that this plan has no intention of replacing.

Each cutover keeps its own rollback: restore the deleted project and previous hook from Git, and re-run the prior gate. Neither repository's rollback touches the other, and neither touches a published RHINO tag.

## Mutual Pinning

RHINO ships a pinned `./hippo` to guard its `cargo` builds. HIPPO will ship a pinned `./rhino` to validate its documentation. The two repositories therefore pin each other.

This is accepted deliberately. Both sides pin **immutable released artifacts** by version, commit, and per-platform checksum, so there is no build cycle and neither repository can break the other in place — a published tag is never replaced. Either side may stay on an old pin indefinitely while the other moves forward, so the cycle cannot deadlock an upgrade: the dependency is on a fixed artifact that already exists, never on the other repository's current `main`.

The one rule this imposes is ordering during delivery. RHINO must reach a tagged release before HIPPO can pin it, and RHINO's own guard pin is unaffected by that release. It is recorded here so a future reader recognizes the mutual pin as a decision rather than an accident, and does not "resolve" it by weakening either bootstrap.

## Rollout Order

Adoption runs BeaverNest, then HIPPO, then grind-in-public, and the order is not arbitrary.

BeaverNest first because its Badakmini is the source of the port, so its findings are the ones with a known-correct expected answer. HIPPO second because it is additive and cannot regress anything — a cheap confirmation that a repository with no prior validator can adopt cleanly. grind-in-public last because its cutover retires an implementation that was written independently, so its findings are the ones most likely to disagree in ways that are genuinely interesting, and by then the tool has three repositories of evidence behind it.

Every repository's adoption is gated on the one before it passing. A finding that requires a tool change sends the change back through the corpus first, and the earlier repositories are re-verified against the new binary before the next one proceeds.

## File Impact

[The cutover design](03-beaver-nest-cutover.md) carries BeaverNest's file impact and [the upstream design](01-rhino-repository.md) carries RHINO's whole tree as new files. The two siblings are listed here so that Phases 9 and 10 name exact paths rather than intentions. Paths are relative to each repository's own root, and every one is discovered against the tree at execution time rather than assumed from this table.

**HIPPO** — additive only; nothing is deleted.

| Disposition | Path                                                                                            |
| ----------- | ----------------------------------------------------------------------------------------------- |
| `[N]`       | `repo-config.yml`                                                                               |
| `[N]`       | `rhino`, `rhino.lock`                                                                           |
| `[E]`       | its quick-gate definition and `.husky/pre-push`, to invoke the new checks                       |
| `[E]`       | `AGENTS.md` and any document naming the gates, only if adoption changes what a contributor runs |

**grind-in-public** — adoption then retirement.

| Disposition | Path                                                                                                                 |
| ----------- | -------------------------------------------------------------------------------------------------------------------- |
| `[N]`       | `repo-config.yml`                                                                                                    |
| `[N]`       | `rhino`, `rhino.lock`                                                                                                |
| `[D]`       | `apps/badakmini-cli/internal/governance/`, `internal/markdownlinks/`, `internal/parity/` and their tests             |
| `[E]`       | `apps/badakmini-cli/` — the module survives; `internal/rulechange/`, `go.mod`, and the Go toolchain all stay         |
| `[E]`       | `apps/badakmini-cli-e2e/` — the module survives; its `rule-change` bindings stay, the three hygiene ones go          |
| `[D]`       | its Gherkin corpus for the retired validator, if it keeps one                                                        |
| `[E]`       | the Nx targets invoking `instruction-size`, `markdown-links`, and `capability-parity`, repointed to the RHINO leaves |
| `[E]`       | its hooks; its Go toolchain setup in CI is **not** removed, because `rule-change` still needs it                     |
| `[E]`       | the thirteen governance surfaces naming the retired validator, through its own propagation transaction               |

Its project-contract, governance-structure, workflow-contract, spelling, and HIPPO bootstrap checks appear in neither table, because this plan does not touch them.

## Propagation Is Per-Repository

Two of the three siblings change what enforces their rules, so each runs its own rules-propagation transaction under its own governance, in its own history. Nothing propagates _across_ repositories: authority does not cross a repository boundary any more than commit authorization does, and a rule repaired here has no standing there.

| Repository      | Propagation                                            | Why                                                                                                                                                                                         |
| --------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BeaverNest      | `repo-governance/workflows/rules-propagation.md`       | Seventeen surfaces name Badakmini as the enforcement mechanism.                                                                                                                             |
| grind-in-public | `repo-governance/workflows/rules/rules-propagation.md` | Thirteen surfaces name its Go validator; its own workflow embeds the retiring gate command too.                                                                                             |
| HIPPO           | None                                                   | It has no rules tree and no rule names a validator. Adoption there adds a check; it does not change a rule, so there is nothing to propagate and inventing a transaction would be ceremony. |

grind-in-public's workflow is split into an inventory, canonical-home, conflict-resolution, and idempotency-gate sequence rather than one document, and its step-4 verification command is — by coincidence of shared lineage — the same `nx run -p badakmini-cli -t test:repo` this plan retires in both places. The transaction is run there with the same ordering constraint as here: the new target works first, so the repaired workflow can verify itself.

The two transactions are independent and are not required to reach the same wording. Each closes its own ledger against its own hierarchy, and each returns its own terminal result.
