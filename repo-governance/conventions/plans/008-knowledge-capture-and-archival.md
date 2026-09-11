# Knowledge Capture and Archival

## learnings.md Is Transient

`learnings.md` is a holding area, not a destination. It exists so that a discovery made mid-execution has somewhere to
go immediately, without stopping to decide where it belongs.

Deciding where it belongs is deferred, not skipped. Before a plan is archived, every entry is resolved: promoted to a
durable owner, or discarded with a reason. "Interesting, keep it here" is not a resolution — it archives the entry into
a folder nobody will open again.

## Durable Owners

An entry is promoted to exactly one owner:

| Owner                   | Fits when the learning is                                   |
| ----------------------- | ----------------------------------------------------------- |
| governance              | a rule that should now bind future work                     |
| specification           | a behaviour that should be stated where behaviour is stated |
| test                    | a case that should fail if the thing regresses              |
| code comment            | context a future reader needs at that exact line            |
| permanent documentation | something a user or operator needs to know                  |
| idea brief              | work worth considering but out of this plan's scope         |

One owner, not several. An entry copied into three places creates three things that can drift, and no rule for which is
authoritative when they do.

A discard is also a resolution, and it carries its reason. "Specific to this plan", "already covered by an existing
rule", "turned out to be wrong" are all legitimate. A silent deletion is not, because the next person to discover the
same thing has no way to learn it was already considered.

## Follow-Ups

A learning that describes work rather than knowledge becomes an idea brief, deduplicated against existing ones. It does
not become an unowned item at the end of the plan, and it does not extend the plan's own scope after execution has
finished.

## Execution Review Precedes Archival

Before a plan is archived, its execution is reviewed against its substantive phases in a fixed order, and the review
records a terminal verdict. Archival is not permitted while any acceptance criterion or delivery unit is unresolved: a
filed plan reads as a finished one, and filing an unfinished plan destroys that signal.

Substantive completion and archival stay separate. A plan can be finished and not yet filed; the reverse must not be
possible.

## The Archival Sequence

Archival is one transaction, in this order:

1. confirm the recorded execution verdict permits it;
2. move the plan folder to `plans/done/YYYY-MM-DD__<slug>`, using the completion date;
3. update every lifecycle index and every live reference to the old path;
4. run the repository's complete validation from the archived state; and
5. commit the move.

Step 3 is the one most often missed and the one most worth doing. A reference to `plans/in-progress/<slug>` that
survives archival points at nothing, and the reader who follows it concludes the plan was deleted rather than finished.

Step 4 runs _after_ the move, not before, because moving the folder is exactly what breaks links.
