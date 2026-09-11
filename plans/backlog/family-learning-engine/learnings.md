# Learnings

Safe, value-free observations captured while planning, and the sections execution must fill. No household record, credential, path, or answer content belongs here.

## Planning observations

- The existing `SifatAllah` module already contains the engine in miniature: mastery rather than completion, a question-level key of the form `"<pair_id>:<kind>"`, a difficult-question queue, and a version-tolerant restore. Generalizing it is mostly renaming concepts into tables; the hard part is the screen, not the model.
- `SifatAllah.restore/1` already upgrades version 1 records into the version 2 key space. Reusing it in the migration rather than reimplementing the upgrade keeps one definition of what a legacy record means, and removes a whole class of conversion defect.
- The existing `sifat_allah.feature` corpus turned out to be the most valuable artefact in this plan. It converts the vague risk "the generic runner will feel worse" into a pass-or-fail gate, which is why merging the bespoke screen into the runner became a defensible decision rather than a gamble.
- Making a mission reusable across topics forces the progress key to drop course and topic. That consequence was not obvious when the hierarchy was first drawn, and it is the single decision most likely to be undone by accident later — hence the constraint recorded in the architecture model rather than only in this plan.
- Two requests arrived after the model was drafted and both had a correctness edge that shaped the design. Coins had to be credited inside the mastery transaction rather than by a subscriber, and that in turn set the boundary for the event model: events notify, transactions decide.

## Open questions

- Whether the review ladder's seven steps suit a child's revision rhythm is a product judgement that only real use will answer. The ladder is deliberately a lookup table indexed by `review_step`, so tuning it later is a constant change and not a data migration.
- Whether `parent_check` needs a reminder path when a submission sits unverified for days. Deferred: the pending queue exists, and a reminder is a subscriber on `verification.requested` once notification work is authorized.
- Whether topics eventually need cross-topic prerequisites. Deliberately excluded here; the placement tables can express it later without a schema change.

## Dependency decision record

Execution fills this with the current primary-source evidence for `absinthe` and `absinthe_plug`: release recency, supported Elixir and OTP range against this repository's toolchain, licence, open advisories, pinned versions, and the rejected built-in alternatives. If the evidence fails, record the switch to the Phoenix JSON fallback here and revise the technical document rather than waiving the check.

## Baseline and rollout evidence

Execution records the routed baseline, the sampling summary from preflight through drain, the migration outcome categories, and the recovery dispositions here. Structural values only.

## Exploratory findings

Filled by the exploratory pass in Phase 6. Each entry records route, state, and category. Record explicitly if none were found.

## Usability findings

Filled by the delegated, spec-blind usability pass in Phase 6, kept separate from exploratory findings. Cross-reference any shared root cause in both sections.
