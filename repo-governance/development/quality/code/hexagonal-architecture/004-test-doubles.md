---
description: >-
  Defines how ports are doubled in tests: hand-written in-memory adapters, one contract suite per stateful port shared by
  the in-memory and real adapters, and which test layer proves each layer.
when_to_use: >-
  Use when testing a facade or domain rule without infrastructure, adding a port or an adapter, or deciding which test
  layer a behaviour belongs to.
---

# Test Doubles

## In-Memory Adapters, Not Mocks

A port is doubled by a hand-written **in-memory adapter** that implements the port and keeps its documented semantics:
ordering, idempotency, revision checks, uniqueness, and pagination. It is not a mock that replays scripted answers.

- An in-memory adapter lives with the test support, never in production code. It holds its state per test, so tests
  stay independent and may run concurrently.
- An effect-only port, such as a sender, a probe, or a notifier, is doubled by a **recording adapter**. The recording
  adapter returns configured answers and records the calls it received, and the test asserts on that record.
- A mock framework that verifies call sequences couples tests to how a use case is written rather than to what it
  decides. It is not used for ports.
- Test-only functions never live in production modules. A seam a test needs belongs in the test support, written
  through the port or the real adapter.

## Contract Suites

A stateful port's semantics are written once, as a **contract suite** parameterized by the adapter under test. The
suite runs twice:

| Run                       | Layer       | Adapter                                              |
| ------------------------- | ----------- | ---------------------------------------------------- |
| proves the double         | unit        | the in-memory adapter                                |
| proves the implementation | integration | the real adapter, against an isolated local resource |

When the two disagree, the contract suite fails on one of them. That is what keeps a fast double honest. A contract
suite sets state up only through the port, and touches no file, process, or network itself.

## Which Layer Proves What

| Layer under test                     | Test layer                                        | Doubles                                                      |
| ------------------------------------ | ------------------------------------------------- | ------------------------------------------------------------ |
| Domain                               | unit                                              | none; it has no dependencies                                 |
| Facade (use cases)                   | unit                                              | in-memory and recording adapters for every port              |
| Outbound adapter                     | integration                                       | none; a real local resource in an isolated, marked test root |
| Inbound adapter                      | integration, through the framework's test harness | real adapters, isolated test data                            |
| A journey across the public boundary | end-to-end, kept few                              | none                                                         |

Coverage thresholds measure the domain and the facades. Adapters are proven by their contract suites and integration
tests, and are named or patterned exclusions in the coverage configuration rather than silently included.

[Quality Gates](../../../quality-gates.md) owns the layer definitions and their gates. This module decides only which
double each layer uses.
