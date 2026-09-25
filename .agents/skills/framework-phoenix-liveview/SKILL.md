---
name: framework-phoenix-liveview
description: >-
  Guides Phoenix LiveView work under its standard: placing logic behind a context, authorizing every live entry point,
  writing for a mount that runs twice, and testing contexts directly and live views through the live test harness.
when_to_use: >-
  Use when writing, changing, or reviewing a Phoenix LiveView, its context, events, forms, or live tests, before the
  first test of the change.
compatibility: Requires a Phoenix application with LiveView, Mix, and ExUnit.
---

# Phoenix LiveView Framework

Every Phoenix LiveView rule is owned by
[Phoenix LiveView Standards](../../../repo-governance/development/quality/stacks/phoenix-liveview-standards.md), which
inherits [Elixir Standards](../../../repo-governance/development/quality/stacks/elixir-standards.md).
[Elixir Programming](../programming-elixir/SKILL.md) carries the Elixir procedure: the Mix gates, tagged tuples,
processes, and concurrent test isolation. This skill adds only the judgement of working at the framework boundary. Where
a sentence here seems to state a rule, the standard decides.

## Start From What the Project Records

Read the router's live sessions and their `on_mount` hooks, and the contexts the feature touches. Run the format check,
the compile with warnings as errors, and the unit run on the untouched tree. A gate already failing is handled under
Preexisting Error Resolution.

## Start in the Context

Write the context function first, test-first, as plain Elixir: its tagged-tuple results, its changeset errors, and its
authorization decision when the context owns one. Only then write the live view that calls it. When a callback grows a
branch on a business rule, or reaches for the repository, the code belongs in the context.

## Authorize Every Entry Point

List the entry points the change adds or alters before writing any of them:

- the route's live session and its `on_mount` hooks;
- `mount/3` for the initial load;
- each `handle_params/3` path, since patching the URL changes what is loaded without a new mount; and
- each `handle_event/3`, since a client can send any event name with any payload, whether or not the template renders
  the control.

For each one, write a test in which a user lacking the permission triggers it and is refused. A new event gets that test
before its success case.

## Write for a Mount That Runs Twice

The first mount renders static HTML and the second runs on the connected socket. Ask of each line in `mount/3`:

| The line                                       | Place it                                          |
| ---------------------------------------------- | ------------------------------------------------- |
| loads what the first paint shows               | both passes                                       |
| subscribes, starts a timer, or sends a message | behind `connected?/1`                             |
| does slow work the first paint can do without  | an async assign, which starts only once connected |

A collection that grows without bound becomes a stream at the point it is introduced, not after memory use is noticed.

## Test at the Framework Boundary

| Under test                                   | Test as                                                         |
| -------------------------------------------- | --------------------------------------------------------------- |
| a context function                           | a unit test, with outbound boundaries replaced                  |
| an event, form, navigation, or authorization | a live test: mount the view, trigger the event, assert elements |
| a component in isolation                     | a render test of the component with its assigns                 |
| a journey across pages in a real browser     | an end-to-end test                                              |

Assert on elements and text a user sees, not on assigns. Form tests submit through the form helper so the test takes the
path a browser would, including field names the template renders. Layers follow
[Quality Gates](../../../repo-governance/development/quality-gates.md).

## Before Handing Off

- the format check, the compile with warnings as errors, and the unit and live test runs all passed;
- no live view or component calls the repository directly;
- every new or changed entry point has its refusal test;
- every subscription or timer in `mount/3` is guarded by `connected?/1`; and
- each recorded red failed on an assertion about the missing behaviour.
