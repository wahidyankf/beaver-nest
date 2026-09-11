# Workflows and Skills

The plan system describes documents; workflows and skills are what act on them. A repository that has adopted the
document rules but cannot groom, execute, review, or archive a plan has adopted half of it.

## Required Capabilities

Seven capabilities cover the lifecycle. Each must be reachable — by a named workflow, an equivalent local procedure, or
a documented decision that it does not apply.

| Stage            | Capability                                                               |
| ---------------- | ------------------------------------------------------------------------ |
| idea grooming    | turn raw ideas into briefs, and retire the ones not worth keeping        |
| backlog grooming | keep backlog plans current, ordered, and still worth doing               |
| plan creation    | author a complete formal plan from a brief or a request                  |
| plan execution   | work through `delivery.md`, recording results as it goes                 |
| quality review   | judge a plan against the specification and return a terminal verdict     |
| execution review | judge finished execution before the plan is archived                     |
| cleanup          | remove the artifacts the work created but the repository should not keep |

Grooming and creation are separate because a brief that survives grooming has been judged worth planning, and a plan
authored from an unexamined idea inherits that lack of judgement.

Quality review and execution review are separate because they ask different questions at different times: whether the
plan is sound before work starts, and whether the work matched the plan after it finishes.

## Workflow, Skill, Agent

Three forms, three responsibilities, no overlap:

| Form         | Owns                                                         |
| ------------ | ------------------------------------------------------------ |
| **workflow** | the sequence — ordered steps, gates, and what ends the stage |
| **skill**    | reusable judgement — how to decide well within those steps   |
| **agent**    | a bounded role with its own tools and its own stopping rule  |

A workflow that also teaches judgement, or a skill that also prescribes sequence, duplicates the other. When both exist
for one concern, the workflow says what happens next and the skill says how to do it well, and neither restates the
other.

## Decision Gates

Planning has two mandatory decision gates: one before authoring begins, one after a complete draft and before the
quality gate. They are sequential and do not merge into a single interview — the questions worth asking before anything
is written are not the questions worth asking about a finished draft.

Each gate presents mutually exclusive choices with exactly one recommendation, always keeps an open-ended alternative
and a discussion alternative available, and records every material decision it resolves. A gate that resolves nothing
was not a gate.

## Retired Names Do Not Linger

When a capability is retired or renamed, the old name is removed rather than aliased. An alias keeps a dead workflow
discoverable, and a repository whose corpus still names it will keep routing work to something that no longer exists.
Every retirement names the replacement owner explicitly, so the behaviour has somewhere to go.
