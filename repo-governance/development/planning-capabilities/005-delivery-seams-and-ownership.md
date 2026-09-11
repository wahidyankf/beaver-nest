# Delivery Seams and Ownership

## What Makes a Valid Seam

A delivery unit is a transaction. A seam between two of them is valid only when the unit on each side has:

1. **one owner** — the repository or component responsible for the change;
2. **one independently testable outcome** — something that can be verified without the other unit landing;
3. **one recoverable transaction** — a rollback that restores a known state on its own; and
4. **one coherent review surface** — a change a reviewer can hold in their head at once.

A split that fails any of the four is not a seam; it is a partition drawn for convenience, and the first failure will
cross it.

Two units that must land together are one unit. Splitting them produces a state where half the work is deployed and the
other half is in review, which is exactly the state neither unit's rollback was designed for.

Conversely, a unit nobody can review is too large regardless of how coherent it is internally.

## Foundation Before Content

Where a unit establishes something later units depend on — a safety layer, a gate, a configuration contract — it lands
first and separately.

Landing them together looks efficient and removes the only opportunity to prove the foundation works on its own. A gate
introduced alongside the content it is meant to check has never been observed passing or failing for its own reasons.

## The Cross-Repository Boundary

A plan may coordinate work across several repositories. Coordination is the only thing that crosses the boundary.

| Crosses           | Does not cross                     |
| ----------------- | ---------------------------------- |
| sequencing        | each repository's own instructions |
| dependency order  | its mutations                      |
| a shared deadline | its proof and its gates            |
|                   | its cleanup                        |

Each repository retains its own instructions, performs its own mutations, produces its own proof, and runs its own
cleanup. A coordinating plan may say _when_ a repository acts; it never says _how_, and it never acts on that
repository's behalf under its own rules.

The reason is ownership, not politeness. A repository's rules exist because of constraints a coordinating plan does not
know about. A plan that overrides them has substituted its own incomplete model for the one that was actually checked.

Coordination also transfers nothing permanently. A repository that participated in a coordinated change is not
thereafter governed by the coordinating plan, and nothing propagates to it automatically afterwards.
