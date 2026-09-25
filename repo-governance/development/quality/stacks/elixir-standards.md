# Elixir Standards

This standard is canonical for Elixir. It holds the choices Elixir and Mix leave open, and an Elixir programming skill
defers here for each rule it applies.

It implements Explicit Over Implicit,
Immutability, Pure Functions, and
Automation Over Manual. Version files and `mix.lock` follow
Native-First Toolchain and
Reproducibility.

## Gates

- **Format:** `mix format --check-formatted`, reading a committed `.formatter.exs`
  ([docs](https://mix.hexdocs.pm/Mix.Tasks.Format.html)).
- **Compile:** `mix compile --warnings-as-errors` ([docs](https://mix.hexdocs.pm/Mix.Tasks.Compile.Elixir.html)). The
  compiler's type checker reports through warnings, so this gate is also the type check.
- **Test load:** `mix test --warnings-as-errors`, so a warning raised while loading the test suite fails the run
  ([docs](https://mix.hexdocs.pm/Mix.Tasks.Test.html)).
- **Lint:** one linter at its strictest level, failing per [Quality Gates](../../quality-gates.md). Example:
  `mix credo --strict` ([Credo](https://github.com/rrrene/credo)).
- **Success typing:** Dialyzer over the declared typespecs, with its persistent lookup table cached between runs.
  Example: dialyxir as a development-only dependency with `:unmatched_returns` and `:error_handling`
  ([dialyxir](https://github.com/jeremyjh/dialyxir)).

A suppression, Dialyzer ignore entries included, states its reason where it applies.

## Type and Boundary Safety

[Type and Boundary Safety](../code/type-and-boundary-safety.md) owns the rule; Elixir maps it as follows.

- The compiler infers types for every construct and warns on a contradiction, but it does not yet read user-written
  signatures ([gradual set-theoretic types](https://elixir.hexdocs.pm/gradual-set-theoretic-types.html)). It checks what
  the code contradicts, never a declared contract.
- Typespecs are that contract. Every public function of a library, and of each boundary module an application exposes,
  declares a `@spec`. The compiler does not check typespecs ([typespecs](https://elixir.hexdocs.pm/typespecs.html)), so
  a spec Dialyzer never analyses is documentation, not evidence.
- External data is cast and validated once into a known shape where it arrives, and no write goes around that step.
  Example: an Ecto changeset.
- External input never becomes an atom: atoms are never collected and the table is finite. Convert against a known set
  with `String.to_existing_atom/1`, or keep the string.

## Failures

A failure a caller can act on returns `{:ok, value}` or `{:error, reason}`, and a `with` chain's `else` matches every
error shape the chain produces. A defect raises. A function offering both forms follows the library convention: `name`
returns the tuple and `name!` raises. `rescue` never drives control flow, and inside a supervised process it never hides
an unexpected failure; the process crashes and its supervisor restarts it from a known state.

Access and matching are assertive: a required key is read with `map.key` or matched, never with `map[:key]` falling back
to `nil`, as the [anti-patterns guide](https://elixir.hexdocs.pm/code-anti-patterns.html) describes.

## Processes

A process exists for state that changes over time, concurrent work, or failure isolation, never to organise code. A
GenServer callback stays thin: it passes the message and state to a pure function and returns what that function
decides, as Functional Core, Imperative Shell requires. Dynamic
processes are named through a registry with a `:via` tuple, never through generated atoms. A supervisor's restart
strategy follows how its children depend on one another.

## Tests

ExUnit is the test framework. Integration tests carry a tag that the test helper excludes from the unit run, keeping the
layers apart as [Quality Gates](../../quality-gates.md) requires. A module is `async: true`
only when it touches no application environment, named process, shared file, or unsandboxed database; each database test
runs in its own sandboxed transaction. Doctests belong to the unit layer.

`mix test --cover` measures lines only, with no branch data. Coverage follows
[Meaningful Coverage](../testing/meaningful-coverage.md): generated modules are listed under `:ignore_modules` with
their reason, partitioned runs are merged with `mix test.coverage` before judging, and any floor is recorded under
[Quality Gates](../../quality-gates.md).

## Documentation

Each public module carries `@moduledoc` and each public function `@doc`, and examples are written as doctests so they
stay true ([writing documentation](https://elixir.hexdocs.pm/writing-documentation.html)). `@doc false` hides an
implementation detail from the reference but never makes it private. A behaviour change updates these with the code, as
[Specification Maintenance](../../specification-maintenance.md) and
Public Contract require.

## Enforcement

An adopter runs the format, compile, test-load, lint, and Dialyzer gates in its own hooks and pipeline. Review applies
the boundary specs, the failure and process rules, test isolation, and the coverage exclusions.
