# Business Requirements: DDD and Hexagonal Architecture Adoption

## Business Goal

Make Bnest cheaper and safer to change. That means a person or a coding agent should be able to answer two questions from
the code's structure alone, without reading the whole application: _where does this belong?_ and _what could this
break?_ Then the build should refuse an answer that is wrong.

Bnest is a 24/7 household service maintained by one owner and by coding agents. Each change is reviewed against
standards, but there is no reviewer with time to hold the whole application in mind, so a rule that only review
enforces is a rule that erodes. That erosion has already happened. Persistence, the filesystem, the network and
operating-system calls appear in domain modules and in LiveViews. One context reaches into another context's store. The
unit test layer writes real database files.

## Roles Served

| Role                                                | Need                                                                                                                                  |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Repository owner                                    | Trust that a merged change did not quietly couple unrelated parts of the household service                                            |
| Coding agent (`swe-code-maker`, `checker`, `fixer`) | A defined, linked standard behind the "Hexagonal Architecture" and "Layers and the Dependency Rule" names it is already told to apply |
| Household member                                    | Nothing visible: the service behaves exactly as before, with no downtime and no forced refresh during release                         |
| Household operator                                  | A release that is an ordinary no-downtime cutover, with the usual rollback                                                            |

## Outcomes

- **O1. The rule exists.** One canonical standard defines bounded contexts, the layers, the dependency rule, ports,
  adapters and application shapes. Every skill, agent and stack standard that names them links to it.
- **O2. The rule is enforced.** A layer or context crossing in `apps/bnest-app` fails the existing `typecheck` gate.
  Infrastructure effects outside adapters fail a test. Neither check needs a reviewer.
- **O3. The code obeys the rule.** Every module of `apps/bnest-app/lib` belongs to a declared boundary. The temporary
  exception list is empty.
- **O4. Tests are honest about their layer.** The unit layer proves domain and application decisions with in-memory
  adapters. Each in-memory adapter is proven equivalent to its real adapter by a shared contract suite.
- **O5. Nothing changed for the household.** All Gherkin scenarios, GraphQL operations and persisted data are
  unchanged. Production serves the new revision after a no-downtime cutover.

## Non-Goals

- New product behaviour, or any change to what a household member sees.
- Event sourcing, CQRS, a message bus, or splitting Bnest into several deployable services.
- Rewriting the raw-SQL stores as Ecto schemas, or changing any table or stored-record format.
- Restructuring the frontend JavaScript, `libs/ex-bdd`, or the e2e projects (their test support only follows module
  renames).

## Business Risks

| Risk                                               | Consequence                              | Mitigation                                                                                                                                                                 |
| -------------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A refactor silently changes behaviour              | A household journey breaks after release | The Gherkin suite runs unchanged at unit and integration level for every unit; affected e2e states run before release; responsiveness sampling and rollback during cutover |
| The migration stalls half-done                     | Two architectures coexist indefinitely   | One exception list, shrinking monotonically, with each context a self-contained pull request; the closure unit requires it empty                                           |
| Enforcement is so strict it blocks legitimate code | Agents work around it with dynamic calls | The standard names the allowed edges explicitly; the layering scan covers the effects `boundary` cannot see                                                                |
| A new dependency becomes a liability               | Upgrade or supply-chain burden           | `boundary` is compile-time only, has no transitive dependencies, and is the established Elixir tool for this; removal deletes declarations and nothing else                |
| Release disturbs the live service                  | Downtime or a forced refresh             | An unchanged migration set and no migration file change, no clustered PubSub between slots, the managed Caddy cutover, a numeric responsiveness budget, and rollback       |
