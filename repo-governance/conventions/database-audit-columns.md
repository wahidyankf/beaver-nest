# Database Audit Columns

Every new relational table in a repository-owned database must record who created, changed, and removed each row, so a stored value can always be traced to an actor and a time without reading application logs.

## Required Columns

A new table must define all six columns:

| Column       | Null          | Meaning                                                             |
| ------------ | ------------- | ------------------------------------------------------------------- |
| `created_at` | never         | ISO-8601 UTC time the row was inserted                              |
| `created_by` | never         | the actor that inserted it                                          |
| `updated_at` | never         | ISO-8601 UTC time of the last change; equals `created_at` at insert |
| `updated_by` | never         | the actor of the last change; equals `created_by` at insert         |
| `deleted_at` | until deleted | ISO-8601 UTC time the row was logically removed                     |
| `deleted_by` | until deleted | the actor that removed it                                           |

`deleted_at` and `deleted_by` must be null together or set together.

## Actor Values

An actor is `user:<user-id>` when a user's request caused the write, or `system:<component>` otherwise, for example `system:scheduler` or `system:release`. An actor value must never be null, empty, or a display name, and must never contain a credential, path, or other private value.

## Soft Deletion

`deleted_at` marks a row as logically absent. Every read must exclude deleted rows unless it exists specifically to inspect them.

A deleted row still occupies its unique keys, so a table with a soft-deletable unique value must express that uniqueness as a partial index excluding deleted rows. Otherwise a removed value can never be reused, which is a defect discovered in production rather than in review.

Soft deletion is not retention: purging deleted rows requires its own explicitly authorized work.

## Exemptions

These columns describe a mutable row's history. Two kinds of table have that history elsewhere, and adding the columns to them creates values that are permanently empty or actively misleading. Both are exempt, and each exemption must be stated in the migration that creates the table and in the plan that introduces it:

- **Append-only logs.** A table whose rows are immutable by database enforcement records its creation time and actor under its own contract and can never be updated. It must not define `updated_at`, `updated_by`, `deleted_at`, or `deleted_by`; a soft-delete column on a system of record invites erasing history that the design exists to preserve. Correction is a compensating record.
- **Projections rebuilt from such a log.** A table that is dropped and recreated by replaying a log has no row lifetime of its own. Its timestamps would report the last rebuild rather than the event, which is fiction rather than audit, and the log already holds the actor and time.

A cursor or checkpoint table that stores only a consumer's position is exempt from every column except `updated_at`.

No other exemption exists. Convenience, row count, and write frequency are not reasons.

## Existing Tables

This convention applies to tables created after it is adopted. A table that predates it should adopt the columns when it is next materially changed; the convention does not require unrelated migration churn.

## Verification

Review every new or changed migration against this convention. Verification passes when each new table defines all six columns or names its exemption and the reason, actor values follow the vocabulary above, paired deletion columns are constrained together, every soft-deletable unique value uses a partial index, and reads exclude deleted rows. Run the affected project's tests and the repository documentation gate:

```sh
./resource-guard run --class ephemeral -- npm exec -- nx run -p badakmini-cli -t test:repo
```
