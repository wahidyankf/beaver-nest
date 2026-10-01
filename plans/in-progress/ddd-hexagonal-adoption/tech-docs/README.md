# Technical Documents: DDD and Hexagonal Architecture Adoption

These documents describe how the adoption is built. Read them in order: each one depends on the ones before it.

1. [Architecture Standard](001-architecture-standard.md) states the rule this plan adopts, where its canonical text
   lives, and every governance and documentation surface that must point at it. It comes first because every later
   document applies it.
2. [Target Architecture and Context Map](002-target-architecture-and-context-map.md) applies the rule to Bnest: the
   boundary topology, the ten bounded contexts, every module's destination, and the inbound adapters.
3. [Boundary Enforcement](003-boundary-enforcement.md) makes the rule mechanical. It covers the `boundary` dependency
   decision, the legacy exception list that lets the migration land context by context, the layering scan, and how
   test support is classified.
4. [Test Doubles and Contract Suites](004-test-doubles-and-contract-suites.md) explains how the unit layer stops
   touching infrastructure without losing confidence: in-memory adapters, proven by contract suites shared with the real
   adapters.
5. [Release, Continuity and Rollback](005-release-continuity-and-rollback.md) covers how the closure revision reaches
   production under the live-service continuity standard.
6. [File Impact](006-file-impact.md) lists every path the plan touches, marked `[E]` edited, `[N]` new, `[M]` moved or
   `[D]` deleted.
7. [Specification Changes](007-specification-changes.md) states which outcomes become durable C4 contracts and
   gives the planned delta to the backend architecture specification.

## Directory Map

- [`001-architecture-standard.md`](001-architecture-standard.md): the adopted rule, its canonical location, and its
  propagation surfaces.
- [`002-target-architecture-and-context-map.md`](002-target-architecture-and-context-map.md): the boundary topology,
  the context map, module destinations, and inbound adapters.
- [`003-boundary-enforcement.md`](003-boundary-enforcement.md): the dependency decision, the legacy exception list,
  the layering scan, test support, and coverage.
- [`004-test-doubles-and-contract-suites.md`](004-test-doubles-and-contract-suites.md): in-memory adapters, contract
  suites, and how the drivers change.
- [`005-release-continuity-and-rollback.md`](005-release-continuity-and-rollback.md): mixed-version safety, the release
  sequence, and rollback triggers.
- [`006-file-impact.md`](006-file-impact.md): every path touched, by unit.
- [`007-specification-changes.md`](007-specification-changes.md): durable-contract dispositions and the C4 delta.
