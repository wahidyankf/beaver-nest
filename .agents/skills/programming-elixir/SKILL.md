---
name: programming-elixir
description: >-
  Guides Elixir work under the Elixir standard: reading what the project records, choosing between a tagged tuple and
  raising, deciding whether a process is warranted, keeping callbacks thin, and isolating concurrent tests.
when_to_use: >-
  Use when writing, changing, or reviewing Elixir code, OTP applications included, before the first test of the change.
compatibility: Requires an Elixir project with Mix and ExUnit.
---

# Elixir Programming

Every Elixir rule is owned by
[Elixir Standards](../../../repo-governance/development/quality/stacks/elixir-standards.md).
[Test-Driven Development](../../../repo-governance/development/test-driven-development.md) and
[Quality Gates](../../../repo-governance/development/quality-gates.md) govern
tests and gates, [Red, Green, Refactor](../../../repo-governance/workflows/red-green-refactor.md) runs each
cycle, and [Developing Applications](../developing-applications/SKILL.md) carries the judgement on layers, errors, logs,
and input that holds in every language. This skill adds only the procedure and judgement of applying them in Elixir.
Where a sentence here seems to state a rule, the standard decides.

## Start From What the Project Records

Read `mix.exs`, `.formatter.exs`, the linter and Dialyzer configuration, the test helper's tag exclusions, and the
choices the adopter recorded. Run the standard's gates on the untouched tree. A gate already failing before any edit is
handled under
Preexisting Error Resolution.

Dialyzer's first analysis is slow; run it once at the start so each later run reads the cached table.

## Reach a Red That Counts

A test calling a missing function raises `UndefinedFunctionError`, and the compiler's warning about the call fails the
test-load gate; neither is a red. Define the function with a body returning a value the assertion rejects, such as
`{:error, :not_implemented}`, and run it.

## Tagged Tuple or Raise

Ask who can act on the failure. When a caller can decide, return the tuple and match each error shape it adds in every
`with` that reaches it. When only a defect produces it, raise. Offer the bang form only where a caller wants failing to
crash.

A `rescue` added to make a test pass is a signal to look again: inside a supervised process, the supervisor restarting
from a known state is usually the handling the design wants.

## Does This Need a Process?

Before writing a GenServer, name its runtime reason: state that changes over time, concurrent work, or failure
isolation. If none applies, a module of functions is the answer. When one does, write the pure function of state and
message first, test it directly, and add the callback that delegates to it last. Keep only a few tests for the process
itself, as
Functional Core, Imperative Shell
intends.

Choose the supervisor strategy from the dependency between children:

| Children                                               | Strategy        |
| ------------------------------------------------------ | --------------- |
| independent of one another                             | `:one_for_one`  |
| each later child depends on the ones started before it | `:rest_for_one` |
| so entangled that none is valid after another restarts | `:one_for_all`  |

## Spot Atoms Built From Input

Search the change for `String.to_atom/1`, atom interpolation such as `:"#{...}"`, and generated process names. Each one
fed by a request, file, or message from outside is a finding the standard names; trace the value back to its source
before deciding.

## Isolate Concurrent Tests

Before marking a module `async: true`, list what it touches: application environment, named processes, shared files, or
the database. Replace a collaborator with an in-memory implementation of its behaviour, as
Test Doubles prefers. A test that passes alone
and fails in the full run usually shares one of those.

## Before Handing Off

- every gate in the standard passed, Dialyzer included;
- each new public function at a boundary has its `@spec` and `@doc`, with an example as a doctest where it helps;
- no atom is created from external input, and every `async: true` module touches no global state; and
- each recorded red failed on an assertion about the missing behaviour.
