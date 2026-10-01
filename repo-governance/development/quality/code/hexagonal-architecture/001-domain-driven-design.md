---
description: >-
  Defines bounded contexts, the ubiquitous language each owns, the context map, published interfaces, and the small
  tactical subset of Domain-Driven Design this repository adopts.
when_to_use: >-
  Use when naming a module or concept, adding a context or deciding which context new behaviour belongs to, or making one
  context call another.
---

# Domain-Driven Design

## Bounded Contexts

A **bounded context** is a part of the system with its own model and its own **ubiquitous language**: the words its
users, its code, its tests and its specifications all use for the same things. A word means one thing inside a context.
Two contexts may use the same word differently, and that is the point of drawing the boundary: neither model is bent to
fit the other.

- Name a context after the capability it gives its users, in their words, not after a technical layer or a table.
- Split a context when one word has started to mean two things inside it, or when two parts change for unrelated
  reasons. Merge two contexts that cannot change one without the other.
- Code, tests, Gherkin and the context's documentation use the context's language. A rename in the language is a rename
  in the code.

## Published Interfaces and the Context Map

Each context publishes one **facade**, its application layer, plus the types callers need to read its results. That is
its whole public surface. Another context or an inbound adapter calls the facade. It never calls the context's ports,
its adapters, or its storage, and it never queries the context's tables.

The **context map** records which context depends on which. Dependencies between contexts form a directed graph without
cycles. When two contexts appear to need each other:

- move the shared concept to the one that owns it;
- or invert the dependency with a port in the provider that the consumer implements, registered by configuration;
- or merge the two, if neither can change without the other.

A supporting context that exists to serve other contexts' adapters, such as storage, is called only from those
adapters, never from another context's domain or facade.

## Tactical Subset

Adopt the tactical patterns only as far as they earn their keep.

- **Entity:** data with an identity that persists across changes. **Value object:** data defined entirely by its
  value. Both are plain data. The function that creates one enforces its invariants and refuses invalid input with a
  typed error.
- **Aggregate:** the unit a repository port loads and saves whole, and the boundary of one consistency rule. A use case
  changes one aggregate per transaction unless the context documents why not.
- **Domain service:** a pure function over entities and values, for a rule that belongs to no single one of them.
- **Repository port:** the port that loads and saves aggregates, named for what it stores, never for its technology.

Layer supertypes, framework base classes, domain events beyond what the system already publishes, event sourcing, and
CQRS are not part of this standard. A plan that wants them argues for them on its own merits.
