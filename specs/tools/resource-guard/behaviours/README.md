# Resource guard behaviours

These scenarios are shared by unit, local integration, and safe compiled-binary E2E adapters. Scenarios tagged `@e2e-exempt` require synthetic pressure or process mutation that is unsafe at the public host boundary; they remain mandatory in unit and integration adapters.

## Directory Map

- [`admission.feature`](admission.feature) specifies admission and resource classification.
- [`execution.feature`](execution.feature) specifies lease and child-process behavior.
- [`public-cli.feature`](public-cli.feature) specifies the safe executable boundary.
- [`release.feature`](release.feature) specifies release-specific capacity evidence.
