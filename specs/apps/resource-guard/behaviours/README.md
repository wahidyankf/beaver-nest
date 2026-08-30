# Resource guard behaviours

These scenarios are shared by unit, local integration, and safe compiled-binary E2E adapters. Scenarios tagged `@e2e-exempt` require synthetic pressure, process mutation, or repository lifecycle access that is unsafe or incapable at the public host boundary. Repository configuration and artifact lifecycle scenarios also use `@unit-exempt` because they require real files or subprocesses; they remain mandatory in the integration adapter. The resource-guard test contract owns an exact approved exemption inventory with a reason for every exempt scenario, so a new, removed, renamed, or unknown exemption fails behavior compliance.

## Directory Map

- [`admission.feature`](admission.feature) specifies admission and resource classification.
- [`artifacts.feature`](artifacts.feature) specifies compiled artifact caching and retention.
- [`execution.feature`](execution.feature) specifies lease and child-process behavior.
- [`public-cli.feature`](public-cli.feature) specifies the safe executable boundary.
- [`portability.feature`](portability.feature) specifies normalized macOS, Linux, cgroup, swap, and PSI evidence.
- [`quality-gates.feature`](quality-gates.feature) specifies strict module-local Go lint and Gherkin adapter enforcement.
- [`release.feature`](release.feature) specifies release-specific capacity evidence.
