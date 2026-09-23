# Docs Propagation

Carry one change into every human-facing document it affects in one bounded pass: stale facts corrected, obsolete documents removed, each fact kept in its one home, and the result readable by a newcomer.

## Entry

Run automatically, as part of the work and without a separate request, whenever a change about to be committed alters what a document's reader relies on, a document is added, moved, or deleted, or the [docs quality gate](docs-quality-gate.md) hands over findings. Edits made inside one run start no second one.

- `change` (required): the revision range or working-tree change.
- `findings` (optional): a handed-over ledger.

The document set is every human-facing document: every `README.md`, the `docs/` and `specs/` trees, documents inside `apps/` and `libs/` projects, standard root files such as `README.md` and `LICENSE`, and plan documents under `plans/` where they describe the repository. Governance and agent instructions stay with [rules propagation](rules-propagation.md). Formatting, links, directory maps, and word budgets stay with the checks the repository already runs; this workflow runs them and adds none.

## Sequence

1. **Freeze the inputs:** the change, any ledger, the Git revision, and uncommitted paths. A material external change ends the run as `input-changed`, never restarting it.
2. **Find what went stale.** Search the whole document set for every name, path, command, flag, version, and interface the change removed, renamed, or redefined. Each ledger row is an item too.
3. **Remove what is obsolete.** Delete a document describing something the repository no longer has, with every link and directory-map entry pointing at it. Move unique meaning that is still true to its canonical home first.
4. **Keep each fact in its one home.** The root README orients; a project README follows [project READMEs](../conventions/project-readmes.md); a map follows [directory maps](../conventions/directory-maps.md); a `docs/` page serves one Diátaxis mode per [documentation architecture](../conventions/documentation-architecture.md). A summary links one level down to its detail per [progressive disclosure](../principles/progressive-disclosure.md), and a fact with a canonical home is linked, never copied.
5. **Write for a newcomer.** Each affected document says from its opening what it is and why it matters, shows the next step without assuming the layout, and leaves no undefined term or skipped prerequisite. Judge this by reading, never by a readability score. A sparing semantic emoji may aid scanning; decoration never does.
6. **Run what is safe to run.** Execute every command and example an affected document shows through its declared Nx target or `./hippo` form. Never run one that touches production or a shared system, publishes, spends, needs a secret, or cannot be undone; the document says plainly that it was not exercised.
7. **Treat specifications as canonical.** Refresh their readability, navigation, and links under [specification maintenance](../development/specification-maintenance.md). When one disagrees with the implementation, apply the partial outcome below.
8. **Change only what is stale, missing, or obsolete.** Never rewrite accurate prose, invent behaviour, or fold in unrelated work.
9. **Verify once** with the repository gate:

   ```sh
   ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo
   ```

   Repair only failures this run caused, and only while their count strictly decreases.

10. **Commit with the change it explains**, per [thematic commits](../conventions/thematic-commits.md). A handed-over ledger's repairs land as their own commit.

## Exit

Outputs: `status` (`no-change`, `landed`, `partial`, or `input-changed`), the updated and removed documents, and each command left unexecuted with its reason.

Partial outcome: when the code, a specification, or the audience is ambiguous or they disagree, that document stays unchanged and the owner is asked through [grill-me](../../.agents/skills/grill-me/SKILL.md) under [last-resort questions](../conventions/last-resort-questions.md); the rest lands. A rerun on unchanged inputs changes nothing. The run authorizes no push.

## One Writer

The gate finds; only propagation writes, so every document edit is made in one bounded place. [Planning](plan-planning.md) adds this workflow to each delivery unit that changes what a document describes.
