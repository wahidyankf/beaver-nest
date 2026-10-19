# Migration Numbers

The entrypoint [Plan Migrations](../plan-migrations.md#migration-numbers) states the four obligations and their reason.
This module holds how each obligation reads in this repository, what observations show it followed or violated, how it
is enforced, and where it came from.

## Scope

The obligations govern every file under `apps/bnest-app/priv/sqlite_repo/migrations/`, and every plan, brief, or other
document that names one.

## Numbers in This Repository

Each migration file is named by a timestamp prefix, such as `20260922000000_add_family_chat_message_reply.exs`. Ecto
records that prefix as the migration's version. Two clauses of the obligations read against that form:

- "next free number" means a version later than every version on `origin/main`, set when the file is created. A
  counter's "one above" does not apply.
- "would sort before one there" replaces "would leave a gap", because timestamps leave no gaps to leave.

The release tool's approved-migration identities, such as `bnest-persistent-schedules-v1`, are ids rather than file
numbers, so the obligations concern the files alone.

## Observations

| Obligation                                    | Followed                                                                      | Violated                                                                                                               |
| --------------------------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 1. New migration takes the next free number   | Its version sorts after every version on `origin/main`, and no file uses it   | Its version already exists on `origin/main`, or sorts before one there                                                 |
| 2. A named number is a hint                   | The document calls the number a hint, or names none                           | The document says the number is reserved, claimed, or fixed, or a migration takes a number because a document named it |
| 3. A taken or out-of-order number is replaced | The migration takes the next free version, and no reference names the old one | The migration keeps a taken version or sorts before one on `origin/main`, or a reference still names the old version   |
| 4. An applied or merged migration is kept     | Its file name is unchanged in the change                                      | A change renames or renumbers such a file                                                                              |

## Reason

A plan is written before its work starts, so it cannot know which number will be free when the work merges. The first
change to merge takes the next free number, and every other change reads `origin/main` when it runs. Ecto keys each
applied migration by version and runs any pending version, so a renumbered applied migration counts as pending and runs
again.

## File Impact

The [Plan Specification Changes](../plan-specification-changes.md#file-impact) convention requires exact File Impact paths. A new migration's path is named as a hint under obligation 2, and execution takes the timestamp under obligation 1. Naming the hint satisfies both, so neither conflicts with the other.

## Enforcement

- **Obligations 1, 3, and 4: unenforced by decision.** A check would compare the change with `origin/main` and read the
  migration directory. `repo-config.yml` declares no gate that does, and a gate declared without an executor would fail
  or never run. The owner decides whether to file that check as separate work.
- **Obligation 2: unenforced by decision.** Whether a sentence reserves a number is a judgement a reader makes.
- **No covered disposition.** The release tool reads one approved migration by path to checksum it. That does not cover
  the rule, because it guards one file and runs only at release.

## Adoption

Adopted from the shared [ose-rules](https://github.com/wahidyankf/ose-rules) catalog at catalog head
`81982e20c798d8af6dbb85ae446d39d0432b6362`, from its
[Plan Migrations](https://github.com/wahidyankf/ose-rules/blob/81982e20c798d8af6dbb85ae446d39d0432b6362/repo-governance/conventions/structure/plan-migrations/001-source-inventory-and-contracts.md)
module (the hint) and its
[Release Cutover](https://github.com/wahidyankf/ose-rules/blob/81982e20c798d8af6dbb85ae446d39d0432b6362/repo-governance/development/quality/delivery/live-service-continuity/002-release-cutover.md)
workflow (take at use). Adaptations:

- One home here, in plan migrations, because plans are where numbers get named. The repository's
  [Live-Service Continuity](../../development/live-service-continuity.md) standard governs cutovers, not numbering.
- The timestamp reading above.
- "By version" in the reason, because Ecto keys applied migrations by version rather than by name.

The obligations are otherwise unchanged.

## Beyond This Repository

No sibling obligation is recorded. This repository declares no parity boundary: its README says `ose-rules` artifacts
are adopted by explicit copy and nothing propagates in either direction. The catalog already holds this rule, so none
is proposed upstream.
