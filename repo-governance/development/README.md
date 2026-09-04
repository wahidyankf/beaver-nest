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
- [Live-service continuity](live-service-continuity.md) prevents working-tree changes and incomplete cutovers from taking an active user surface offline.
- [Quality gates](quality-gates.md) define unit, local-only integration, dedicated-app E2E, coverage, and Git hook safeguards.
- [Resource-aware development](resource-aware-development.md) admits and sheds only repository-owned work under unsafe host pressure.
- [Software quality enforcement](software-quality-enforcement.md) maps each maintained quality outcome to its blocking, scheduled, runtime, or evidence route.
- [Specification maintenance](specification-maintenance.md) keeps every relevant artifact under `specs/` synchronized with application changes.
- [Test-driven development](test-driven-development.md) requires app and library behaviour to be developed through red–green–refactor cycles.
- [Test identities](test-identities.md) isolates synthetic accounts and makes cleanup safe and deterministic.
