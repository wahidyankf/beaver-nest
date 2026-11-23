---
description: >-
  Indexes the ordered modules of the test and gate contract: registry and dispatch, surface placement, pull-request
  scope, test levels and targets, the behaviour corpus, the coverage floor, and the conformance record.
when_to_use: >-
  Use to locate the module holding one rule of the test and gate contract, such as surface placement or the coverage
  floor.
---

# Test and Gate Contract Modules

The modules below are read in sequence and carry the full statement of each rule indexed by the
[Test and Gate Contract](../test-and-gate-contract.md) entrypoint.

| Module                                                    | Holds                                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [Registry and Dispatch](001-registry-and-dispatch.md)     | C1 to C5: one declaration, no dead entries, installed hooks, pins, offline gates      |
| [Surface Placement](002-surface-placement.md)             | C6, C8 to C11: each surface's work, allowed lists, landing gate, messages, leaks      |
| [Pull-Request Scope](003-pull-request-scope.md)           | C7: affected-project, changed-file, and global scope, with a classification table     |
| [Test Levels and Targets](004-test-levels-and-targets.md) | C12, C14, C17, C18, C21: levels, targets, automatic homes, hermetic enforcement       |
| [Behaviour Corpus](005-behaviour-corpus.md)               | C13: corpus layout, binding convention, exemptions, spec review, behaviour inventory  |
| [Coverage Floor](006-coverage-floor.md)                   | C15: the 99% unit floor, uncombined levels, categories, and instrument choice         |
| [Conformance Record](007-conformance-record.md)           | C16, C19, C20, C22 to C24: lint, inventory, delivery, required check, diagrams, scope |

## Directory Map

- [001 Registry and Dispatch](001-registry-and-dispatch.md)
- [002 Surface Placement](002-surface-placement.md)
- [003 Pull-Request Scope](003-pull-request-scope.md)
- [004 Test Levels and Targets](004-test-levels-and-targets.md)
- [005 Behaviour Corpus](005-behaviour-corpus.md)
- [006 Coverage Floor](006-coverage-floor.md)
- [007 Conformance Record](007-conformance-record.md)
