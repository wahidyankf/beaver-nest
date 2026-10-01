---
description: >-
  Defines the four application shapes a bounded context may take and which layers each needs, and the implementation
  stages that order work inside one.
when_to_use: >-
  Use when creating a context or deciding whether a context needs ports and adapters, a long-lived process, or only a
  pure library, and when ordering the work of a new behaviour.
---

# Application Shapes

Not every context needs every layer. Choose the smallest shape that holds its behaviour, and grow it when the behaviour
grows. A layer with nothing in it is not drawn.

| Shape                  | Use when                                                                     | Layers                                                                                                                               |
| ---------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Pure library           | the context computes and keeps no state and performs no effect               | domain, plus a facade if it has more than one caller                                                                                 |
| Port-backed context    | the context reads or writes state, or performs an effect                     | facade, domain, ports, adapters                                                                                                      |
| Process-backed context | the context also owns a long-lived process: a cache, a scheduler, a session  | as port-backed; the process belongs to the application layer, delegates decisions to the domain and effects to ports, and stays thin |
| Supporting context     | the context exists to serve other contexts' adapters, such as a record store | as port-backed; consumers depend on its facade only from their own adapters                                                          |

A pure library becomes port-backed the first time one of its callers wants it to remember something. Move the
persistence out of the caller and into a port of the context, rather than letting each caller persist the library's
values its own way.

## Implementation Stages

Work in this order. Each stage ends with a passing test, and a stage is never skipped because the next one is tempting.

1. **Place.** Name the context and decide what is decided (domain), what is needed from outside (a port), and what
   triggers it (an inbound adapter). A new effect always starts as a port.
2. **Specify.** Write the behaviour where the repository's specification rule requires it, then the failing test at the
   narrowest layer that can prove it. For a decision, that is a domain or facade test with in-memory adapters.
3. **Decide.** Implement the domain and facade until the test passes.
4. **Connect.** Implement or extend the outbound adapter, proven by its contract suite against a real local resource.
   Wire it in the composition root.
5. **Expose.** Implement the inbound adapter, proven through the framework's own test harness.
6. **Refactor** while every layer stays green, and only then optimize, on a measurement.

[Test-Driven Development](../../../test-driven-development.md) owns the red, green, refactor cycle inside each stage.
