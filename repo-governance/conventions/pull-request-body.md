# Pull Request Body

Every pull request here is read by a human, whatever else reviews it. The body is where the change explains itself, and the [merge preconditions](pull-request-merge.md) assume it is accurate.

## What It Carries

- The outcome and the problem it solves, rather than a list of edits. A reader has to be able to judge whether the change answers the problem.
- What is in scope and what is deliberately not, each with its reason. A non-goal without a reason reads as an oversight; with one it is a decision.
- Where to start reading, and which paths to skip — generated mirrors and mechanical churn named explicitly.
- What was verified, what risk remains, and the rollback or containment step.
- Why this is one natural [delivery seam](pull-request-boundaries.md): the cohesive purpose, why the included artefacts had to land together, and that unrelated purposes were excluded. Never a line or file count.
- Why the resulting `main` state is deployable, including any flag's enabled and disabled paths and its removal record.

A rules-and-documentation change carries all of this too. It is most of this repository's traffic, and without the obligation its body would decay into a changelog.

## It Never Goes Stale

Every push that moves the head updates the body in the same step, before the head is treated as reviewable. A body describing a diff the head no longer has is stale evidence exactly as an earlier gate run is, and it misleads the one reader the preconditions cannot replace. Rewriting it is also how a scope that grew during the work gets stated rather than smuggled.

## Enforcement

Unenforced by tooling, by decision. No check can tell whether a stated reason is the real one or whether a body still matches its diff. The obligation is the author's, and a body contradicted by the diff it ships is a legitimate finding for any review that runs.
