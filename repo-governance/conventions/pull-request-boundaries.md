# Pull Request Boundaries

One branch, one pull request, one delivery unit. Never open two pull requests from one branch, and never drive one pull request from two branches.

A **delivery unit** is the contiguous run of work ending at a point where what has accumulated is an independently shippable increment. The unit, not the individual phase or task, is what becomes a pull request.

## Where a Pull Request Opens

- A pull request opens at a delivery boundary, not at every phase. Work inside a unit still passes its own checkpoint, but opens nothing. Pushing the branch to `origin` for durability opens nothing either.
- A plan declares its delivery boundaries and its work location — the `worktrees/<name>/` checkout its execution uses — when it is written, and a plan predating this requirement records both at execution start. Execution never runs from the primary checkout, except the release invocation the [integration path](integration-path.md) exempts, and a branch chosen at invocation is valid only inside that worktree. The last change-producing phase is always a boundary; otherwise the plan's final work never reaches `main`. A setup or baseline phase that produces nothing reviewable is never a boundary — move any reviewable work it acquired into the first real unit.
- Independent work delivers separately. Grouping is permitted only along a dependency chain; folding two independent pieces into one pull request to reduce their number re-serializes work that was independent.
- A ready increment is never held to batch it with later work, and an open pull request is never parked to merge with others at the end.

## The Boundary Test

A point in the work is a delivery boundary when all four hold:

- **Coherent** — the accumulated increment is a complete unit of meaning: a capability, a migration step, a governance rule. Not half a refactor.
- **Green alone** — every applicable gate passes on the increment by itself.
- **Deployable** — the exact resulting `main` state satisfies the deployable-state rule below.
- **Reviewable whole** — a reviewer can judge it without reading work that does not exist yet.

Anything failing one of them is intermediate rather than a boundary: a schema nothing reads yet, a helper the next step consumes, a fixture the next step asserts on.

## Where to Draw the Seam

Split at a natural cohesive seam: one independently useful purpose a reviewer can hold in mind, which this repository can build, verify, operate, and roll back without an unmerged sibling. Line counts and file counts never create, erase, or force a boundary — a large unit is right when its parts must land together, and a small diff carrying two unrelated purposes must still split.

Keep everything that unit needs to stay internally consistent in it: source, tests, specifications, migrations, documentation, governance text, generated artefacts, operational configuration, and rollback support. Separating them is wrong whenever either side would be left incomplete, contradictory, or unsafe. A directory or surface boundary is not by itself a seam, and unrelated purposes stay apart even when they touch the same file.

Units land sequentially in the one worktree the work provisions: land a unit, sync that worktree from `origin/main`, then begin the next. Each unit is reviewed against a base that already contains its dependencies, never stacked on an unmerged sibling.

## Deployable State

Bnest is a live service, so merge a unit only when the exact resulting `main` state is safe to deploy immediately. Complete user-reachable behaviour may be active. Incomplete behaviour must be complete and inert behind a temporary flag disabled in production, with both paths tested and its rollout, rollback, and removal recorded. A flag controls exposure of an otherwise complete increment; it never excuses half-built behaviour, a broken enabled path, a missing dependency, or an unsafe migration. Work that cannot meet this test stays inside the unit it depends on rather than merging as scaffolding a later pull request would make safe.

The [body](pull-request-body.md) justifies the seam and the deployable state.

## Enforcement

Unenforced by tooling, by decision. No diff-size check can tell whether a seam is natural or a resulting state is deployable. The `Quality gate` check and the [pull-request merge convention](pull-request-merge.md) supply supporting evidence; the judgement stays with the author and reviewer, recorded in the pull request body.
