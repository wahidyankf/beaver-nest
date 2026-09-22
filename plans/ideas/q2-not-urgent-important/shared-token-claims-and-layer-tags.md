# Shared Token Claims and Layer Tags

Two governance proposals raised by the `family-chat-message-reply` execution: what it means for a specification to
say a surface uses a shared token, and what a scenario's layer tag obliges. Provenance: execution learnings
captured 2026-09-22.

## Problem / Context

**A shared-token claim is about the cascade, not only the pixels.** Tech-doc 003 said the reply surfaces use "the
room's existing focus ring". Five of them did not — they fell back to the user-agent default, reporting
`auto 1px rgb(0, 95, 204)` where the controls beside them reported `solid 3px rgb(247, 184, 75)`. The suites were
green, because nothing asserts a focus ring, and the prose was satisfied on a reading that only asked whether
_a_ ring appeared. The repair was to add the five selectors to the room's existing rule rather than restate its
values, so the claim became true of the stylesheet and not only of the rendering. A related trap sits beside it:
an inline style longhand outranks any stylesheet rule, so a position written inline cannot be overridden by the
media query that is supposed to replace it — which is how an open menu carried desktop coordinates into a layout
that should have made it a sheet.

**A layer tag is a binding obligation, not a label.** `BnestApp.Behaviour.FeVitestUnitScope` prunes every
`@fe-vitest-unit` scenario from the Elixir corpus, and `assets/test/behaviour/verify.ts` then requires exactly that
complementary set. So the tag does not describe where a scenario is proven — it _moves_ the scenario, and every
tagged scenario needs a binding in the frontend harness even when its real proof is a browser. The plan's file
impact never named that third binding file; reading the harness did. The corpus already worked this way, but
nothing states it, so it is learned by a red gate.

## Why Now

Both are cheap to write down and were each found by accident during one execution. Neither is urgent: the specific
defects are fixed, and the tag behaviour is correct — it is only undocumented.

## Prior Art / Precedents

- [Specification maintenance](../../../repo-governance/development/specification-maintenance.md) already fixes the
  Gherkin → bindings → red → code → smoke order; the tag obligation is a missing sentence in that story rather
  than a new rule.
- The repository's [software quality map](../../../repo-governance/development/software-quality-enforcement.md)
  already insists that manual inspection is not substitutable by tests, which is exactly how the focus-ring gap
  was found.

## Proposed Direction (Sketch)

1. A short convention line: when a specification says a surface uses a shared token, the implementation satisfies
   it by _referencing_ the shared rule, not by re-deriving its values — and a reviewer checks the selector list,
   not a screenshot. Add the inline-longhand corollary: anything a media query must be able to override belongs in
   a custom property, never an inline longhand.
2. A short line in specification maintenance: `@fe-vitest-unit` moves a scenario between corpora and therefore
   obliges a frontend binding, including for scenarios whose substantive proof is a browser.

## Rough Scope & Non-Goals

In scope: two documentation additions and, if it is cheap, a RHINO check that a scenario carrying the tag has a
binding in the frontend harness.

Out of scope: changing the pruning mechanism, which works; and any new automated check for focus rings, which is
the sort of assertion that passes while looking at nothing.

## Risks & Open Questions

- The focus-ring rule is easy to state and hard to enforce mechanically. It may be worth no more than a sentence
  and a reviewer's habit; pretending otherwise invites a check that cannot fail.
- Whether the tag obligation belongs in specification maintenance or in the ExBdd project's own README depends on
  who reads which, and that is genuinely unsettled.

## What Success Looks Like + Promotion Signal

Success: a specification that names a shared token is satisfied by joining the rule that defines it, and a scenario
that carries a layer tag arrives with the binding that tag requires — both without anyone rediscovering it from a
red gate or a manual pass.

Promotion signal: a second surface found using a default focus ring while claiming the shared one, or a second
plan whose file impact misses a binding file, promotes this brief to a plan.
