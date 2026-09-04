# Business Requirements

## Goal

Allow repository work to begin from Codex, Claude Code, or OpenCode while preserving the same committed rules, reusable workflows, safety boundaries, and required repository capabilities.

## Roles

- **Repository contributor:** chooses an available harness and expects the repository workflow to remain governed and executable.
- **Repository maintainer:** changes shared instructions, skills, agents, or capabilities once and receives deterministic drift findings.
- **Automation operator:** relies on Nx and pre-push gates to reject an incomplete harness contract before integration.

## Required Outcomes

- One canonical repository instruction entry point applies to all supported harnesses.
- Every canonical repository skill is discoverable or reached through a verified thin adapter in every supported harness.
- Every canonical custom agent and required MCP capability has a verified harness adapter.
- The initial agent set includes the existing CI monitor and a read-only web researcher with the same source-quality workflow in every harness.
- Badakmini reports exact paths and reasons when committed harness artifacts are missing, malformed, extra, or divergent.
- Badakmini performs no generation, mutation, model inference, authentication, or network access.
- Documentation makes supported and deliberately non-equal concerns explicit.

## Non-goals

- Equalize proprietary system prompts, built-in tools, model quality, approval UX, or billing.
- Copy user-global preferences into the repository.
- Replace existing Nx targets with harness-specific scripts.
- Change Bnest end-user behaviour or its Codex SDK runtime.

## Constraints

- The public repository must contain no credentials or machine-specific paths.
- Canonical content must not be duplicated merely to satisfy a harness adapter.
- Adapter formats may differ, but their declared source, identity, and required capability must reconcile deterministically.
- The web-research workflow must check repository evidence first, prefer primary sources, cite claims, expose conflicts and gaps, and never edit files.
- Existing Codex behaviour must remain supported while Claude Code and OpenCode are added.
- New Badakmini behaviour follows Gherkin-first implementation with complete unit, integration, and E2E adapters.

## Risks

- Harness file formats and discovery rules may change independently.
- A thin adapter may be syntactically valid but unavailable because a user disables project settings or skills.
- Harnesses expose different agent permission primitives; the implementation must encode the strongest equivalent read-only restriction each supports and document any vendor-owned enforcement boundary.
- Claude's lack of native `.agents/skills/` discovery can create wrapper drift without validation.
- Parsing too much vendor configuration would turn Badakmini into a general-purpose config interpreter.
- User-global instructions can still add or override behaviour beyond the repository-owned baseline.

## Success

Success means all three harnesses have a documented, committed route to the same canonical repository contract, the focused Badakmini command and full repository gate pass, deliberate drift fixtures fail at every test layer, and no implementation claims equality for machine-local or vendor-owned behaviour.
