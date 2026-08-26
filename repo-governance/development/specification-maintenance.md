# Specification Maintenance

Application specifications under `specs/` must remain synchronized with the implemented system. Before changing application production code, tests, configuration, or user-facing project documentation, inspect the relevant specification subtree and assess every artifact in it for impact.

Update every affected specification file in the same change and before implementation. A file is affected when the change would make any of its behavior, actor, boundary, responsibility, relationship, interface, data flow, data store, constraint, example, vocabulary, or ownership statements inaccurate, incomplete, or contradictory.

Applicable artifacts include:

- C4 models governed by the [architecture specification standard](architecture-specifications.md);
- executable Gherkin governed by the [BDD standard](behaviour-driven-development.md);
- specification READMEs and directory maps governed by the [directory-map convention](../conventions/directory-maps.md); and
- any other canonical model, contract, schema, example, or reference stored in the affected subtree.

Do not churn an unaffected specification merely because its sibling changed. When adding, removing, moving, or renaming a specification artifact, update its directory map in the same change.

Follow each artifact's more specific ordering and verification requirements. In particular, observable behavior still follows Gherkin and red bindings before implementation, while architectural changes keep every affected C4 view and constraint synchronized with the final as-built state.

Run applicable project tests and the repository specification-map gate:

```sh
npm exec -- nx run -p badakmini-cli -t test:repo
```

The delivery report must identify the specification files updated or state that the impact check found no required specification change.
