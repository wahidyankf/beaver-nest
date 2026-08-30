# Plan Migrations

Use this convention when a formal plan moves, copies, normalizes, replaces, or retires runtime, browser, schema, API, protocol, configuration, or dependency data. It makes preservation and recovery executable before implementation begins.

## Technical Documentation

In an unsplit plan, sections of `tech-docs.md` identify current state separately from the proposed target and own exact old/new shapes when schemas change. In a naturally split technical set, use mapped `tech-docs/migration-design.md` and `tech-docs/data-contracts.md` companions when migration flow and data contracts have distinct reader jobs. Inventory every affected source with its location/key, readers and writers, accepted shape/version and limits, owner, destination, compatibility behavior, and disposition proof. Link repository evidence where safe; never copy private values into the plan.

Describe the transition in this order:

1. **Expand:** add the new reader, writer, schema, or location without removing the old one.
2. **Migrate:** copy immutable source data with an idempotent identity, validation, and observable outcome.
3. **Verify:** read the accepted target through the normal product flow and rehearse restore from its verified immutable recovery source.
4. **Contract:** retain compatibility for a stated window. Put any archival or deletion in a later explicitly authorized plan.

State the rollback reader/writer behavior, mixed-version boundary, retry behavior, recovery-source/manifest evidence, and manual verification. Treat unknown or malformed sources as preserved opaque records with a reported outcome; never coerce, discard, or overwrite them to make a migration appear successful.

## Delivery

Before migration, inventory actual sources without adding private values to Git or fixtures. Delivery checkpoints must prove every inventory entry is either retained unchanged, copied and verified, or reported safely for retry. A plan may not claim data preservation while an affected reader, writer, source shape, owner, or fallback remains unaccounted for.
