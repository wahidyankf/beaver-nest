---
description: >-
  Places application code by bounded context and by layer: a pure domain, ports the application needs, adapters that
  alone touch infrastructure, and inbound adapters that only call a context's facade, with dependencies pointing inward.
when_to_use: >-
  Use when deciding where new application code belongs, adding an effect or an integration, splitting or naming a
  context, choosing a test double, or reviewing a change for a layer or context crossing.
---

# Hexagonal Architecture

Code that decides and code that does age at different speeds, and so do the parts of a system that speak different
languages. This standard keeps them apart: **Domain-Driven Design** says which part of the system a piece of code
belongs to, and **Hexagonal Architecture** (Ports and Adapters) says which layer inside that part. The two answer the
same question, "where does this belong?", so they are one standard.

It implements Explicit Over Implicit, Fail Closed, and
[Progressive Disclosure](../../../principles/progressive-disclosure.md). It holds the language-neutral rule. Each stack
standard maps it to its own tools and states no second copy.

## The Rule in One Table

| Layer                | Holds                                                                               | Depends on                                     | Never                                                                   |
| -------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| Domain               | entities, value objects, policies, invariants                                       | the language's standard library                | performs an effect, reads a clock or the environment, knows a framework |
| Ports                | the interfaces the application needs from outside                                   | domain                                         | contains an implementation                                              |
| Application (facade) | use cases: validate, authorize, load, decide, save, publish                         | domain, its own ports, other contexts' facades | calls infrastructure, chooses an adapter, chooses a transport status    |
| Outbound adapters    | port implementations over a database, file, network, process, clock, or message bus | domain, ports, infrastructure libraries        | holds a business rule                                                   |
| Inbound adapters     | web, API, CLI, scheduler task, release entry point                                  | facades and exported types                     | reaches a port, an adapter, or a store                                  |

Source dependencies point inward. Configuration, the composition root, is the only place that names which adapter
implements which port.

## Modules

Read in order. The [module map](hexagonal-architecture/README.md) indexes them.

1. [Domain-Driven Design](hexagonal-architecture/001-domain-driven-design.md): bounded contexts, ubiquitous language,
   the context map, published interfaces, and the tactical subset adopted.
2. [Layers and the Dependency Rule](hexagonal-architecture/002-layers-and-the-dependency-rule.md): each layer's
   contract, the composition root, and Functional Core, Imperative Shell.
3. [Application Shapes](hexagonal-architecture/003-application-shapes.md): which layers a context needs, and
   Implementation Stages.
4. [Test Doubles](hexagonal-architecture/004-test-doubles.md): in-memory adapters, contract suites, and which layer
   proves what.

## Enforcement

The adopter enforces the dependency rule mechanically wherever its stack allows, so that a crossing fails a gate rather
than waiting for a reviewer. The stack standard names that mechanism and its gate. Enforcement has two parts:

- a compile-time or lint-time boundary check for module dependencies;
- a source scan for the effects such a check cannot see, typically calls into the standard library.

Review covers what neither sees: whether a context's language is coherent, whether a rule sits in the domain rather
than in an adapter, and whether a new context or port is warranted at all.
