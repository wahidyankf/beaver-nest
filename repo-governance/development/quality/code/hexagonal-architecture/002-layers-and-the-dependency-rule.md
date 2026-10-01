---
description: >-
  Defines each layer's contract inside a bounded context, the dependency rule that points every source dependency
  inward, the composition root, and Functional Core, Imperative Shell.
when_to_use: >-
  Use when placing a new function or module, adding an effect or integration, wiring an adapter, or reviewing an import
  that crosses a layer.
---

# Layers and the Dependency Rule

## The Dependency Rule

Source dependencies point inward: inbound adapters → facade → domain, and outbound adapters → ports → domain. An inner
layer never names an outer one. When an inner layer needs something from the outside world, it declares a **port** and
receives an implementation. It never reaches for the implementation itself.

## Layer Contracts

- **Domain.** Pure. It receives everything it needs as a parameter, including the current time, identifiers, and
  configuration values. It returns values or typed errors. It holds every business rule and invariant, and no effect: no
  database, file, network, process, environment, clock, randomness, logging, or framework call.
- **Ports.** One interface per need, named for the capability ("room store", "push sender", "capacity probe"), never for
  a technology. A port documents the semantics every implementation must keep: ordering, idempotency, concurrency, and
  failure values. A port carries no implementation.
- **Application (facade).** One public module per context. Each public function is one use case:
  1. validate input arriving from an untrusted source;
  2. authorize the actor;
  3. load through a port;
  4. decide in the domain;
  5. save through a port;
  6. publish.

  It translates adapter failures into the context's own errors, so infrastructure error types stop at the adapter. It
  never builds a query, opens a file, or chooses a transport status. A context that owns a long-lived process keeps that
  process here and keeps it thin.

- **Outbound adapters.** Each implements one port over one technology and holds no business rule. Its own tests prove
  it against a real local resource.
- **Inbound adapters.** Each translates one external event into one facade call and one facade result into the
  transport's response. A web handler, a GraphQL resolver, a CLI task, a scheduled task, and a release entry point are
  all inbound adapters.

## Composition Root

Exactly one place, the application's configuration plus its supervision start-up, names which adapter implements which
port, in each environment. The facade resolves its ports from that configuration at run time, so no compile-time
dependency runs from application to adapter. Switching an adapter is a configuration change, never a code change in
the facade.

## Functional Core, Imperative Shell

The same rule seen inside one use case. Gather the inputs (the shell: adapters, the clock, the request), call a pure
function that decides (the core: the domain), then carry out what it decided (the shell again). A function that both
decides and acts is split along that line. Misplacement shows early:

- a domain function that wants a clock, a connection, or a logger;
- an adapter holding a condition about a business rule;
- a facade choosing an HTTP status.

## Errors and Logs Across Layers

An expected failure travels as a value through domain and application. An adapter converts its infrastructure failure
into the port's failure value once. A failure becomes a transport response once, in the inbound adapter. A failure is
logged once, where it is finally handled, and logging is an effect, so it stays in an adapter or the shell.
