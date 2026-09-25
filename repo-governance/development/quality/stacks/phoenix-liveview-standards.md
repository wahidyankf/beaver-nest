---
description: >-
  Fixes Phoenix LiveView stack choices on top of the Elixir baseline: logic behind contexts, verified routes,
  authorization at every live entry point, a two-pass mount, streams for large collections, forms from changesets, and
  tests through the framework's live test harness.
when_to_use: >-
  Use when building, structuring, or reviewing a Phoenix LiveView application, or when authorizing a live event,
  rendering a form or a large collection, or testing a live view.
---

# Phoenix LiveView Standards

This standard is canonical for Phoenix with LiveView and holds only the choices the framework leaves open. It inherits
[Elixir Standards](elixir-standards.md), whose gates, failure forms, process rules, and test isolation apply unchanged,
and a Phoenix LiveView framework skill defers here for each rule it applies.

It implements Fail Closed,
Explicit Over Implicit, and
Pure Functions.

## Gates

The Elixir gates run over the web layer too. Paths are written as
[verified routes](https://phoenix.hexdocs.pm/Phoenix.VerifiedRoutes.html) (`~p`), which the compiler checks against the
router, so a link to a route that does not exist fails the warnings gate instead of a user's click.

## Contexts Own the Application

A live view, controller, or component calls the public functions of a
[context](https://phoenix.hexdocs.pm/contexts.html) module and never reaches the repository or a schema query directly.
The context is the application boundary: it holds the decisions, returns tagged tuples, and knows nothing about sockets,
assigns, or templates, as Functional Core, Imperative Shell
requires. A callback translates an event into one context call and the result into assigns.

## Type and Boundary Safety

[Type and Boundary Safety](../code/type-and-boundary-safety.md) owns the rule; in LiveView it maps as follows.

- **Every entry point is untrusted.** Parameters and event payloads reach `mount/3`, `handle_params/3`, and
  `handle_event/3` from the client, which can send any event with any payload. Each of the three authorizes the action
  it performs, as the [security model](https://phoenix-live-view.hexdocs.pm/security-model.html) requires; authorizing
  only in `mount/3` leaves every later event open. Shared checks run as `on_mount` hooks declared for a `live_session`,
  and routes needing different authorization sit in different sessions.
- **Logging out ends live sessions.** A user's live sockets carry an identifier, and logging out or revoking access
  disconnects them, since a connected live view otherwise keeps the access it had.
- **External data is cast.** Input from the client passes through a changeset built with
  [`cast/4`](https://ecto.hexdocs.pm/Ecto.Changeset.html), naming the permitted fields; `change/2` is kept for data the
  application produced itself. Input with no schema uses a schemaless changeset rather than raw map access.

## Lifecycle and Rendering

- **Mount runs twice.** The first mount renders over plain HTTP, and the second runs once the socket connects.
  Subscriptions, timers, and work that should run once are guarded by `connected?/1`, and neither pass assumes the other
  happened.
- **Large or growing collections are streams.** A list the server need not keep in memory is a stream, so the socket
  holds no copy of every row; assigns hold only what later renders read.
- **Forms render from a form value.** A template renders `@form` built with `to_form/2` from a changeset, never the
  changeset itself, and shows a field's errors only once the user has interacted with it, per the
  [form bindings](https://phoenix-live-view.hexdocs.pm/form-bindings.html).

## Tests

Layers follow [Quality Gates](../../quality-gates.md).

- Context functions are unit-tested as plain Elixir, with outbound boundaries replaced per
  Test Doubles.
- A live view is tested through the framework's
  [live test harness](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveViewTest.html), which drives the endpoint
  pipeline in-process: it mounts the view, triggers events and form submissions, and asserts on rendered elements.
  Because it runs the framework pipeline, it is an integration test. Each authorization rule gets a test where the event
  is sent by a user who lacks the permission.

What coverage measures follows [Meaningful Coverage](../testing/meaningful-coverage.md); generated framework scaffolding
that holds no decision is a named exclusion.

## Documentation

Each context's public functions are its documented interface, carrying module and function documentation. A live view
documents the events it handles where the template alone does not make them clear.

## Enforcement

The Elixir gates enforce formatting, warnings, and route verification in the adopter's own build, hooks, and pipeline.
Review applies context boundaries, per-entry-point authorization, the two-pass mount, and stream use.
