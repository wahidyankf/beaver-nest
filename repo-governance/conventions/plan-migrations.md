# Plan Migrations

Use this convention when a formal plan moves, copies, normalizes, replaces, or retires runtime, browser, schema, API, protocol, configuration, or dependency data. It makes preservation and recovery executable before implementation begins.

## Technical Documentation

In an unsplit plan, sections of `tech-docs.md` identify current state separately from the proposed target and own exact old/new shapes when schemas change. In a naturally split technical set, use mapped `tech-docs/migration-design.md` and `tech-docs/data-contracts.md` companions when migration flow and data contracts have distinct reader jobs. Inventory every affected source with its location/key, readers and writers, accepted shape/version and limits, owner, destination, compatibility behavior, and disposition proof. Link repository evidence where safe; never copy private values into the plan.

### Data-Model Visualization

Every formal plan that adds, changes, or removes a persistent database schema must place a readable data-model visualization beside the exact schema contract. Use an ERD for a relational model and show affected entities, primary/foreign/unique keys, relationships, and cardinalities; a single-entity change still shows that entity and the keys or adjacent ownership context needed to understand it. For a document, key/value, event, graph, or other non-relational model, use the equivalent diagram that shows affected records, keys, references, and ownership boundaries.

The diagram aids comprehension but never replaces exact old/new fields, types, constraints, defaults, compatibility, validation, migration, rollback, or tests. Keep critical meaning searchable in surrounding prose and follow the repository's [Markdown visualization convention](markdown-visualizations.md).

### Field Guide

Every schema contract must include a field-by-field guide for every column, property, or key in each affected resulting table or record. Explain each field's purpose in plain language and document any non-obvious value shape, unit or timezone, owner or producer, required/null/default behavior, and creation, update, clearing, or retention lifecycle. Identify primary, foreign, and unique keys, references, sensitive values, and fields whose counters or lifecycle semantics could otherwise be misread.

The guide supplements rather than repeats the exact schema: use plain language for intent and lifecycle while DDL or the equivalent contract remains authoritative for types and constraints. Do not rely on a field name alone to convey meaning.

Describe the transition in this order:

1. **Expand:** add the new reader, writer, schema, or location without removing the old one.
2. **Migrate:** copy immutable source data with an idempotent identity, validation, and observable outcome.
3. **Verify:** read the accepted target through the normal product flow and rehearse restore from its verified immutable recovery source.
4. **Contract:** retain compatibility for a stated window. Put any archival or deletion in a later explicitly authorized plan.

For an authority or retirement cutover, verification must boot a fresh process from persisted target configuration, make the prior source unavailable in an isolated fixture, and execute every affected critical reader and writer through normal product boundaries. Prove the target remains authoritative and fails closed instead of falling back. Row counts, schema presence, migration summaries, adapter-only calls, and same-process state are insufficient.

State the rollback reader/writer behavior, mixed-version boundary, retry behavior, recovery-source/manifest evidence, and manual verification. Treat unknown or malformed sources as preserved opaque records with a reported outcome; never coerce, discard, or overwrite them to make a migration appear successful.

## Delivery

Before migration, inventory actual sources without adding private values to Git or fixtures. Delivery checkpoints must prove every inventory entry is either retained unchanged, copied and verified, or reported safely for retry. A plan may not claim data preservation while an affected reader, writer, source shape, owner, or fallback remains unaccounted for.
