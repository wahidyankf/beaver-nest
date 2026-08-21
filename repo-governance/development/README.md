# Development Standards

Development governance defines how repository changes are designed, implemented, tested, reviewed, and maintained. It may cover code quality, dependencies, compatibility, security, testing, and local development practices.

Development standards are subordinate to the repository [vision](../vision/README.md), [principles](../principles/README.md), and [conventions](../conventions/README.md), and take precedence over [workflows](../workflows/README.md). A development standard must change if it conflicts with any higher level; a workflow must change if it conflicts with a development standard.

When a standard requires an ordered procedure, link to a reusable workflow instead of duplicating its steps.

A development standard should identify:

- the changes or components it applies to;
- the required behavior or quality bar;
- how compliance is verified; and
- justified exceptions, when permitted.

## Directory Map

- [Quality gates](quality-gates.md) standardize project checks, coverage, end-to-end verification, and Git hook safeguards.
- [Test-driven development](test-driven-development.md) requires app and library behavior to be developed through red–green–refactor cycles.
