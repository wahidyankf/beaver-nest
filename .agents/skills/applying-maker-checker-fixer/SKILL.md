---
name: applying-maker-checker-fixer
description: >-
  Guides the judgement inside a make, check, and fix loop: which role a request calls for, how applied findings are
  re-validated, when an edit counts as a fix, and when a disagreement leaves the loop for a person.
when_to_use: >-
  Use when acting as a maker, checker, or fixer in a quality loop, or when deciding which of those roles a request
  needs.
compatibility: Requires read access to the content under review and to the report being acted on.
---

# Applying Maker, Checker, and Fixer

The check-fix workflows own the loop:
Specs Quality Gate and its siblings say what runs,
in what order, and when it stops.
Finding Criticality and Confidence
owns the scales. This skill covers the judgement each role needs inside that loop.

## Three Roles, Three Questions

| Role    | Asks                                                        | Never                         |
| ------- | ----------------------------------------------------------- | ----------------------------- |
| maker   | what should exist, and what else must change with it        | grades its own output as done |
| checker | does the content meet the rules it is held to               | edits what it judges          |
| fixer   | which confirmed findings are safe to apply without a person | creates content from scratch  |

A request to create or substantially reshape content is a maker's job. A report of rule violations is a fixer's. A
finding that needs taste, restructuring, or context nobody recorded is neither: it goes to the maker or a person, and a
fixer that attempts it produces confident damage.

A checker never edits what it judges, for the reason
Agent Authoring gives: once it edits, nothing
independent is left to judge the edit.

## Re-Validate From the Evidence

A fixer treats every finding as a claim about an earlier state. It rereads the current file, confirms the problem at the
stated place under the stated rule, and rates confidence one finding at a time, never per file or per report.

Where the checker cited an external source, the fixer reads that citation instead of repeating the research. When the
repository and the citation together cannot confirm the finding, the honest rating is `MEDIUM`, not a guess.

Only an objective finding, one a reader can confirm without an opinion, earns `HIGH`. Wording, flow, and emphasis stay
`MEDIUM` however obvious the better version looks.

## An Edit Is Not Yet a Fix

Pattern substitutions report success when nothing matched, so a logged fix can describe an unchanged file. After each
edit, read the target again and confirm the new content is there; when it is not, record the fix as failed. Reshaping
across several lines calls for a tool that fails loudly on a non-match rather than one that silently skips.

## Accepted False Positives Stay Accepted

A checker has no memory between runs. Without a record, it raises the same disproved finding every cycle, and the loop
spends each cycle dismissing it again. Record each accepted false positive under a key that survives edits: category,
file, and a short description, never a line number. How the record is kept and consumed belongs to
[Generating Validation Reports](../generating-validation-reports/SKILL.md).

## Repeated Disagreement Leaves the Loop

When a finding accepted as a false positive is raised again, neither apply it nor dismiss it a second time. Two runs
reading the same rule differently means the rule, or the checker's reading of it, is ambiguous. Record the finding once
for a person who owns the rule, and take it out of the loop's count.

## Stable, Not Empty

A clean report after a fix can mean the checker skipped what the fix touched. The workflows ask for two consecutive
clean validations for that reason. A count that stops falling usually means a non-deterministic check or a scope that
grows while it is fixed, and another identical cycle will not change either;
Bounded Convergence decides what happens next.

## Planning Has No Separate Fixer

This pattern is recorded as contradicting the planning roster, and planning wins inside its own scope.
[Skill and Agent Roster](../../../repo-governance/development/planning-capabilities/002-skill-and-agent-roster.md)
has the plan maker apply validated findings itself, within the repair budget of
[Plan Quality Gate](../../../repo-governance/workflows/plan-quality-gate.md), because a loop waiting for an empty
report can always reach one.

Outside planning, a workflow may declare a dedicated fixer. In both arrangements, whoever applies findings uses the
judgement above.
