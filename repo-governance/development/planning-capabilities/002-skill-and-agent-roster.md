# Skill and Agent Roster

## Skills

| Skill                           | Owns                                                        |
| ------------------------------- | ----------------------------------------------------------- |
| `grill-me`                      | the shared decision protocol both planning gates use        |
| `plan-creating-project-plans`   | how to author the six documents well                        |
| `plan-grooming-idea-briefs`     | how to judge whether a brief is worth promoting             |
| `plan-writing-gherkin-criteria` | how to write acceptance criteria that are actually testable |
| `plan-validating-quality`       | how to judge a draft beyond what structure can be checked   |
| `plan-verifying-execution`      | how to judge finished execution against the repository      |

## Agents

| Agent                    | Owns                                                           |
| ------------------------ | -------------------------------------------------------------- |
| `plan-maker`             | authoring a plan end to end, including its own bounded repairs |
| `plan-checker`           | auditing a draft against the specification                     |
| `plan-execution-checker` | auditing finished execution before archival                    |

There is no separate fixer agent. The maker incorporates validated findings itself, within the repair budget the
[Quality Gate](../../workflows/plan-quality-gate.md) declares.

A maker–checker–fixer triangle sounds safer and is not: it creates a workflow that waits for a reviewer to return an
empty report, and "no findings" is a state a sufficiently persistent loop can always reach. Bounding the repairs and
ending on a terminal verdict is the property that actually holds.

## Exactly Once, In One Form

Each capability appears once, in one form, with one responsibility:

- a **workflow** owns sequence;
- a **skill** owns reusable judgement; and
- an **agent** owns a bounded role with its own tools and stopping rule.

Where a workflow and a skill cover the same concern, the workflow says what happens next and the skill says how to do it
well. Neither restates the other. Two artifacts holding the same guidance will drift, and nothing decides which one an
agent should have believed.

## Adapters Are Generated, Never Authored

A harness that needs its own file format gets a **generated** adapter, derived from the canonical artifact. The adapter
holds no authored body of its own.

This is the rule most often broken by accident. Copying a skill body into a harness-specific file works immediately and
fails silently later: the canonical artifact is edited, the copy is not, and the harness keeps teaching the old
behaviour with no signal that it is stale.

## Presence Is a Declared Choice

A repository that cannot or should not expose one of these — no agent harness, no Gherkin criteria, a locally equivalent
capability under another name — records that. The record names the supported equivalent, or states why the capability is
not applicable.

An absent capability with no record is not a decision. It is indistinguishable from an incomplete adoption, and the
whole point of the record is that a future reader can tell those apart.
