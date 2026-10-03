# 001: Architecture Standard

## What Is Adopted

Two ideas, held as one language-neutral standard, because in this repository they answer one question together: where
does a piece of code belong?

**Domain-Driven Design, strategic part.**

- A **bounded context** is a part of the system with its own ubiquitous language and its own model. The same word
  ("adapter", "message", "session") may mean different things in two contexts, and each context's code uses its own
  meaning.
- A **context map** records which context depends on which, and how.
- Contexts integrate only through a context's **published interface** (its facade and the types it exports), never
  through its internals or its storage.

**Domain-Driven Design, tactical part, adopted only as far as it earns its keep.**

- **Entities** and **value objects** are plain data with the invariants enforced by the functions that create them.
- An **aggregate** is the unit a repository port loads and saves whole.
- **Domain services** are pure functions over those types.
- No layer supertype and no framework base classes.

**Hexagonal Architecture (Ports and Adapters).** Inside a context:

| Layer                    | Holds                                                                                                   | May depend on                                                  | Must not                                                             |
| ------------------------ | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------------- |
| Domain                   | entities, value objects, policies, invariants                                                           | nothing outside the domain and the language's standard library | perform an effect, read a clock or the environment, know a framework |
| Ports                    | behaviours (interfaces) the application needs from the outside world                                    | domain                                                         | contain an implementation                                            |
| Application (the facade) | use cases: validate, authorize, load through a port, decide in the domain, save through a port, publish | domain, ports, other contexts' facades                         | call infrastructure, choose an adapter, choose a transport status    |
| Adapters, outbound       | port implementations: SQL, filesystem, HTTP, OS processes, clocks, PubSub                               | domain, ports, infrastructure libraries                        | hold a business rule                                                 |
| Adapters, inbound        | web, GraphQL, CLI, scheduler task, release entry points                                                 | the facade and exported types                                  | reach a port, an adapter or a store                                  |

**The Dependency Rule:** source dependencies point inward. Domain ← application ← adapters. Configuration (the
**composition root**) is the only place that names which adapter implements which port.

**Functional Core, Imperative Shell** is the same rule seen from inside a function. Decisions are pure and receive
everything as parameters, including `now`; effects happen at the edges.

**Application Shapes.** Not every context needs every layer.

| Shape                             | Use when                                                          | Layers                                                                      |
| --------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Pure library                      | no state, no effect                                               | Domain only, plus a facade                                                  |
| Port-backed context               | state or effects                                                  | Facade, Domain, Ports, Adapters                                             |
| Process-backed context            | the context owns a long-lived process (cache, scheduler, session) | As port-backed; the process is part of the application layer and stays thin |
| Supporting/infrastructure context | the context exists to serve other contexts' adapters (storage)    | As port-backed; consumers depend on it only from their adapters             |

**Test Doubles.**

- A port is doubled by a hand-written in-memory adapter, not a mock framework.
- Each in-memory adapter of a stateful port is proven against the real adapter by one shared contract suite.
- The unit layer uses doubles. The integration layer uses real adapters against local resources.

**Implementation Stages.** Place first, then write the failing test at the narrowest layer, then implement. A new effect
starts as a port.

## Where the Canonical Text Lives

The rule is canonical in `repo-governance/development/quality/code/`, beside
[Type and Boundary Safety](../../../../repo-governance/development/quality/code/type-and-boundary-safety.md). That folder
holds language-neutral rules that every stack standard maps to its own tools.

| Path                                                                                          | Content                                                                                      |
| --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `repo-governance/development/quality/code/hexagonal-architecture.md`                          | Entry: scope, the dependency rule, the layer table, and enforcement. Links to its modules    |
| `repo-governance/development/quality/code/hexagonal-architecture/001-domain-driven-design.md` | Bounded contexts, ubiquitous language, context map, published interface, the tactical subset |
| `.../hexagonal-architecture/002-layers-and-the-dependency-rule.md`                            | Layers, the dependency rule, composition root, Functional Core and Imperative Shell          |
| `.../hexagonal-architecture/003-application-shapes.md`                                        | The four shapes and how to choose one                                                        |
| `.../hexagonal-architecture/004-test-doubles.md`                                              | In-memory adapters, contract suites, layer placement                                         |
| `.../hexagonal-architecture/README.md`                                                        | Directory map of the modules                                                                 |

The module split exists because rhino's 750-word budget applies to every `repo-governance/**/*.md`. The entry plus
numbered modules follows the pattern already used by `plans.md` and `stack-packs.md`.

## Stack Mapping

- **Elixir** ([`elixir-standards.md`](../../../../repo-governance/development/quality/stacks/elixir-standards.md)):
  - a port is a `@behaviour` module under `<Context>.Ports`;
  - an adapter is `@behaviour`-annotated and lives under `<Context>.Adapters`;
  - adapters are wired with `config :bnest_app, <Context>, <port_key>: Adapter` and resolved by the facade with
    `Application.fetch_env!/2`;
  - enforcement uses the `boundary` compiler plus the layering scan.
- **Phoenix LiveView**
  ([`phoenix-liveview-standards.md`](../../../../repo-governance/development/quality/stacks/phoenix-liveview-standards.md)):
  "Contexts Own the Application" is amended to say that a Phoenix context is the facade of one bounded context. Live
  views, controllers, resolvers and plugs are inbound adapters.
- **TypeScript**
  ([`typescript-standards.md`](../../../../repo-governance/development/quality/stacks/typescript-standards.md)): its
  existing "Functional Core, Imperative Shell or, where ports exist, Hexagonal Architecture" sentence gains links. No
  TypeScript enforcement is added; the Nx module-boundary rule stays a deviation because no project carries tags.

## Propagation Surfaces

Every surface that names the rule gets a link or a pointer, in the same unit (U2):

| Surface                                                                                            | Change                                                                                                                                                     |
| -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.agents/skills/developing-applications/SKILL.md`                                                  | Link the six names                                                                                                                                         |
| `.agents/agents/swe-code-maker.md`, `swe-code-checker.md`, `swe-code-fixer.md`                     | Link the names they cite; the checker's check 1 cites the scan and the boundary gate as evidence                                                           |
| `.agents/skills/programming-elixir/SKILL.md`, `.agents/skills/framework-phoenix-liveview/SKILL.md` | Link where they cite placement                                                                                                                             |
| `repo-governance/development/quality/stacks/{elixir,phoenix-liveview,typescript}-standards.md`     | Link, and the Phoenix amendment above                                                                                                                      |
| `repo-governance/development/quality/stacks/repository-adapter.md`                                 | Adopter decision: `boundary` for Elixir; the deviation now reads "no Nx project carries tags; Elixir boundaries are enforced by `boundary`"                |
| `repo-governance/development/quality/code/README.md`                                               | Directory map entry                                                                                                                                        |
| `repo-governance/development/software-quality-enforcement.md`                                      | One row: architecture → `typecheck` (boundary) + layering scan in `test:integration` + review                                                              |
| `AGENTS.md`                                                                                        | One link line under Development (the word budget is tight)                                                                                                 |
| `docs/explanation/hexagonal-architecture.md` + `docs/explanation/README.md`                        | Why: the problem, the rule, Bnest's context map as a diagram                                                                                               |
| `docs/reference/glossary.md`                                                                       | Disambiguate "Adapter" (BDD binding adapter vs hexagonal adapter), "Aggregate" (test/target aggregate vs DDD aggregate); add bounded context, port, facade |
| `docs/reference/software-development.md`                                                           | Add the standard to the language-neutral list                                                                                                              |
| `specs/apps/bnest/app-be/architecture.md`                                                          | C4 component view regrouped by bounded context (U14, as-built)                                                                                             |

The [rules-propagation](../../../../repo-governance/workflows/quality/rules-propagation.md) and
[docs-propagation](../../../../repo-governance/workflows/quality/docs-propagation.md) workflows each run once in U2 and record a
terminal result. `.claude` route adapters are regenerated only if a skill or agent name or description changes. This
plan changes content only, so no route adapter is renamed. U2 still runs `./rhino harness adapters generate` after the
skill and agent edits, because their content digests change, then validates and commits whatever it rewrote.
