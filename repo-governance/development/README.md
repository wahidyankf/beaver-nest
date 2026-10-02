# Development Standards

Development governance defines how repository changes are designed, implemented, tested, reviewed, and maintained. It may cover code quality, dependencies, compatibility, security, testing, and local development practices.

Development standards are subordinate to the repository [vision](../vision/README.md), [principles](../principles/README.md), and [conventions](../conventions/README.md), and take precedence over [workflows](../workflows/README.md). A development standard must change if it conflicts with any higher level; a workflow must change if it conflicts with a development standard.

When a standard requires an ordered procedure, link to a reusable workflow instead of duplicating its steps.

A development standard should identify:

- the changes or components it applies to;
- the required behaviour or quality bar;
- how compliance is verified; and
- justified exceptions, when permitted.

## Directory Map

- [Architecture specifications](architecture-specifications.md) keep each application's canonical C4 model synchronized with implemented boundaries and relationships.
- [API testing](api-testing.md) requires layered automated proof and manual `curl` confirmation for every affected REST, GraphQL, or other HTTP operation.
- [Behaviour-driven development](behaviour-driven-development.md) governs executable Gherkin specifications and adapter-specific binding contracts.
- [Dependency selection](dependency-selection.md) prefers standard-library and existing mechanisms and limits external packages to necessary, established, maintained choices.
- [End-to-end testing](end-to-end-testing.md) limits slow public-boundary tests to affected journeys during development and schedules full-suite coverage.
- [GitHub Actions storage](github-actions-storage.md) bounds artifacts, Packages, and caches and requires an externally verified zero-dollar Actions hard stop.
- [Live-service continuity](live-service-continuity.md) prevents working-tree changes and incomplete cutovers from taking an active user surface offline.
- [Planning capabilities](planning-capabilities.md) name the planning workflows, skills, and agents a repository publishes and the uniform contract each satisfies.
- [Planning capabilities modules](planning-capabilities/README.md) hold the ordered modules of that roster.
- [Quality standards](quality/README.md) hold the adopted language-neutral standards, stack packs, and repository adapter.
- [Quality gates](quality-gates.md) define unit, local-only integration, dedicated-app E2E, coverage, and Git hook safeguards.
- [Quality gate adapter](quality-gate-adapter.md) records how this repository adopted the shared quality-gate contract: families, callers, tools, owners, and deviations.
- [Quality gate contract](quality-gate-contract.md) defines the one bounded, advisory contract every `<family>-quality-gate` follows.
- [Quality gate contract modules](quality-gate-contract/README.md) hold inputs and scoring, sequence and termination, and verdicts and ledger.
- [Resource-aware development](resource-aware-development.md) coordinates repository-owned work through shared vector reservations, FIFO admission, and targeted shedding.
- [Software quality enforcement](software-quality-enforcement.md) maps each maintained quality outcome to its blocking, scheduled, runtime, or evidence route.
- [Sole-writer propagation](sole-writer-propagation.md) holds the rules every `<family>-propagation`, the one writer of its family, shares.
- [Specification maintenance](specification-maintenance.md) keeps every relevant artifact under `specs/` synchronized with application changes.
- [Test-driven development](test-driven-development.md) requires app and library behaviour to be developed through red–green–refactor cycles.
- [Test identities](test-identities.md) isolates synthetic accounts and makes cleanup safe and deterministic.
- [Upstream tool defects](upstream-tool-defects.md) routes each HIPPO, RHINO, or FERRET defect to its owner as an idea brief, or, when it blocks with no workaround, as a bug-fix plan landed there first.
