# RHINO Adoption Across the OSE Repositories

Extend the four-repository RHINO cutover to `ose-public` and `ose-private`, and settle whether `ose-public`'s own
`rhino-cli` merges into RHINO or stays.

_Recorded 2026-09-08, on completion of [the RHINO CLI extraction plan](../../done/README.md). Every figure below is
carried from that plan's `learnings.md` rather than re-estimated._

## Problem / Context

The same documentation-hygiene validator has now been written **four** times: `ose-public`'s `rhino-cli` (Go, then
Rust, now F#), BeaverNest's Badakmini (F#), grind-in-public's `badak-mini` (Go), and RHINO (Rust). Three of the four
are retired or superseded — the extraction plan removed **5,044 lines of F# and 3,949 lines of Go** and replaced both
with one checksum-pinned binary now consumed by BeaverNest, HIPPO, and grind-in-public.

`ose-public`'s `rhino-cli` is the fourth, and it is the one the extraction plan deliberately did not touch. The
Phase 1 alignment reading compared the two surfaces command by command and found **six agreements and eight
deliberate divergences**, each with a recorded reason: `--output text|json|markdown` against `text|json`; a `--say`
echo flag RHINO answers with `version --json`; exit `1` against exit `2` for an invalid `--output` value, because
RHINO reserves `1` for findings so a gate can read the code without knowing which leaf ran; a configuration scope
covering a monorepo's whole automation registry against a standalone tool's policy input; and one `resolved_tree`
snake_case key in an otherwise kebab-case schema.

None of those eight is a disagreement about what documentation hygiene _is_. They are the differences between a
monorepo's internal automation surface and a distributable tool — which is exactly the question a merge has to
answer, and the reason it was left out of a plan already retiring two implementations.

## Why Now

Not urgent, and deliberately so. The pressure that justified the extraction — three independent implementations
drifting — is now resolved for three repositories. What remains is one more implementation of the same checks in a
repository nobody is currently changing.

The signal to act would be either of: `ose-public` needing a change to `rhino-cli` that RHINO already implements, or
a fifth repository wanting these checks. Until then the cost of a merge exceeds the cost of two implementations
that are not both moving.

## Prior Art / Precedents

- **The extraction plan itself** is the direct precedent, including its own partial-retirement case: grind-in-public
  kept `harness rule-change`, because that check reads staged paths and harness pre-edit payloads and is excluded by
  RHINO's read-only, network-free, process-free posture. Any `ose-public` merge needs the same inventory —
  _what the tool provides_, not _what the gate runs_, a distinction that plan learned twice by getting it wrong.
- **HIPPO's distribution model**, which RHINO copied: a checksum-pinned release, a committed lock file, and a
  bootstrap script that verifies before executing. Proven across three consumers on four platforms.
- **The degenerate-consumer result**: HIPPO declares no harness roster, no `CLAUDE.md`, and no adapter directories,
  and adopting RHINO there required making `instruction-adapter` optional rather than special-casing. A repository
  with a different shape is a configuration entry, not a fork.

## Proposed Direction (Sketch)

Three questions in order, each answerable before the next is worth asking.

1. **Is `rhino-cli`'s configuration scope in scope at all?** It registers harnesses, specs structure, an environment
   contract, gate surfaces, a gate registry, and model grades. RHINO validates documentation and harness parity from
   a declared policy. If most of `rhino-cli` is monorepo automation rather than hygiene, the answer is not a merge
   but a **split**: the hygiene leaves adopt RHINO, the automation registry stays where it is.
2. **Can the eight divergences be reconciled without weakening either?** Some are cheap (`markdown` output, the
   `resolved_tree` key). One is not: the exit-code contract. RHINO's `1`/`2` split is load-bearing for every consumer
   gate written so far and would not be given up.
3. **Only then, adoption.** Same shape as Phases 9–10: transcribe the existing policy into `repo-config.yml` with
   each value's source recorded, reconcile both validators over the real tree before retiring anything, verify the
   cutover with injected violations, rehearse the rollback, and propagate through that repository's own rules.

`ose-private` is a straight adoption with no retirement, on the Phase 9 (HIPPO) pattern, and does not depend on any
of the above.

## Rough Scope & Non-Goals

**In scope:** the alignment decision for `rhino-cli`; RHINO adoption in `ose-public` and `ose-private`; whatever
upstream configuration keys those two trees prove RHINO is still missing.

**Not in scope:** re-opening the eight recorded divergences as open questions — they have reasons, and a merge
argues against a reason or accepts it. Not in scope either: making RHINO run processes, write, or reach the network
to absorb a check that needs to; such a check stays where it is, as `rule-change` did.

## Risks & Open Questions

- **The merge may be the wrong shape.** If `rhino-cli` is mostly automation registry, forcing it into a
  policy-input tool would import a monorepo's concerns into a standalone binary and make every other consumer pay
  for them. Question 1 exists to kill the merge early if so.
- **A fifth consumer may find a fifth degenerate case.** Two of three did: HIPPO's absent adapters, grind-in-public's
  zero diagrams and its `opencode.json` instructions field, which needed `v0.1.3`. Budget for at least one upstream
  release per new tree.
- **Retiring a fourth implementation is not free.** grind-in-public's cutover surfaced six dangling documentation
  links and a retired command name that exited `0`; both were found by verification rather than review.
- **Open:** does `ose-public` want a dependency on a repository outside itself at all? RHINO is MIT and pinned by
  checksum, but that is a governance answer, not a technical one.

## What Success Looks Like + Promotion Signal

Success is **one implementation of documentation hygiene across every OSE repository**, each pinned by checksum to
the same released tag, with whatever genuinely is not hygiene left where it belongs and said so out loud.

**Promote to a plan when** either trigger fires — a needed `rhino-cli` change RHINO already implements, or a fifth
repository wanting these checks — _and_ question 1 has an answer. Promoting before question 1 would produce a plan
whose first phase might dissolve it.
