# Ideas Grooming

## Entry

`plans/ideas/` holds at least one brief, and someone needs to know which of them are still worth anything.

## Sequence

1. **Freeze the list.** Enumerate every brief in `plans/ideas/` before judging any of them. A brief added during
   grooming belongs to the next pass, not this one — otherwise the list never closes.
2. **Read each brief once.** A brief that cannot be understood in one reading has a defect worth recording; that is
   itself a grooming outcome.
3. **Assign exactly one disposition** per brief:

   | Disposition | Means                                                           |
   | ----------- | --------------------------------------------------------------- |
   | promote     | worth planning now; it becomes a formal plan in the backlog     |
   | keep        | still worth doing eventually, and here is what would trigger it |
   | retire      | not worth doing, and here is why                                |

4. **Record the reason** for every `keep` and every `retire`. A `keep` without a trigger is indistinguishable from
   indecision, and it will be re-read at every future grooming pass at the same cost.
5. **Promote by authoring, not by moving.** A promoted brief is the input to [Planning](plan-planning.md); the brief
   itself does not become the plan. Move the brief only after the plan exists.
6. **Delete retired briefs.** Version control is the archive. A retired brief left in place will be reconsidered by
   someone who does not know it was already rejected.

## Exit

Every brief on the frozen list carries a disposition, and every `keep` and `retire` carries a reason.

## What This Does Not Do

It does not size, schedule, or sequence work. A promoted brief has been judged worth planning; whether it is planned
next is [Backlog Grooming](plan-backlog-grooming.md)'s question.

It does not improve briefs. A brief too vague to judge is retired or rewritten, and rewriting it is authoring — the same
work as writing it the first time.
