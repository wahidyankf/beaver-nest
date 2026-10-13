# Dependency Graph and Recovery

## Sequence Is Not Dependency

A checklist is written in some order, and only part of that order is load-bearing. `delivery.md` therefore expresses its
phases and items as a dependency graph: nodes are phases and items, edges are `blocked by` relations, independent nodes
may run concurrently, and dependent nodes run in sequence.

Left implicit, dependency gets inferred from list position. The executor then serializes work that never needed to wait,
or runs concurrently work that did.

## The Parallelization Model

Every plan with more than one phase, or with any node that runs concurrently with another, carries a
`## Parallelization Model` section before its first phase, stating:

- which nodes are concurrent and which are serial, with the reason for each serial edge — a node reads what another
  writes, not merely that it is listed later;
- the concurrency cap the plan declares, and why the plan departs from it where it does; and
- cleanup as the terminal node, depending on every delivery node, so cleanup never removes a working copy, branch, or
  artifact that an in-flight node still needs. Cleanup completes, and is recorded, before the archival move, so no
  cleanup record is ever added to a plan in `done/`, per
  [Dev Artifact Clean-Up](../../workflows/maintenance/dev-artifact-clean-up.md).

Two nodes are independent only when neither reads what the other writes. A shared output file, a shared branch, or a
shared ordering constraint makes them dependent, however separable they look.

Where a plan coordinates several repositories, the graph carries sequencing and dependency order only;
[Delivery Seams and Ownership](../../development/planning-capabilities/005-delivery-seams-and-ownership.md)
fixes what never crosses that boundary.

## A Reference Belongs to the Unit That Makes It Resolvable

A cross-reference is a read: a link to a document, a configuration key naming a surface, an adapter naming a driver.
Written in an earlier delivery unit than its target, it creates a backwards edge that no merge conflict reveals. It
surfaces instead as a failing gate on a change that is internally correct, because a validator reads the declaration
literally and finds its target absent.

Name the target in prose now, and add the reference in the unit that creates the target. Never add an exemption to let
an early reference pass.

## Conditional Recovery

A recovery or rollback item runs only if something goes wrong, so it cannot be resolved like an ordinary item. Each one
names:

| Element        | Holds                                           |
| -------------- | ----------------------------------------------- |
| trigger        | the observable condition that activates it      |
| decision owner | who judges that the trigger has fired           |
| procedure      | the exact steps, written before they are needed |
| proof          | what shows the recovery restored a known state  |

Naming a decision owner does not change the executor label, which still follows
[Executor Authority](../../development/planning-capabilities/004-executor-authority.md).

The item stays dormant until its trigger fires. At reconciliation it closes with one terminal disposition: executed,
with its proof; or `Not triggered`, with the evidence that the trigger stayed false.

```markdown
- [ ] [AI] Roll back the importer release — trigger: error rate above the declared ceiling for ten minutes; owner:
      release owner; procedure: `<rollback-procedure-path>`; proof: the previous version serving traffic.
  > Not triggered — YYYY-MM-DD: the error rate stayed below the ceiling for the whole observation window;
  > `<metrics-evidence-path>`.
```

The disposition closes the item, not the checkbox. An item with no disposition is ambiguous: skipped, forgotten, and
never needed look identical. A bare tick is worse, because it claims a recovery ran when it did not.

Whether a reference resolves depends on the main line when its unit lands, so no plan-time check can decide it, and
dependency order stays a review question per [Structural Validation](006-structural-validation.md).
