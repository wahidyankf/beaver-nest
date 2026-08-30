# Resource guard behaviours

These scenarios are shared by unit, local integration, and safe compiled-binary E2E adapters. Scenarios tagged `@e2e-exempt` require synthetic pressure, process mutation, or repository lifecycle access that is unsafe or incapable at the public host boundary. Artifact lifecycle scenarios also use `@unit-exempt` because they require real files and subprocesses; they remain mandatory in the integration adapter.

## Directory Map

- [`admission.feature`](admission.feature) specifies admission and resource classification.
- [`artifacts.feature`](artifacts.feature) specifies compiled artifact caching and retention.
- [`execution.feature`](execution.feature) specifies lease and child-process behavior.
- [`public-cli.feature`](public-cli.feature) specifies the safe executable boundary.
- [`release.feature`](release.feature) specifies release-specific capacity evidence.
