# Checks Adoption

Adopted check standards from the shared catalog `ose-rules` at `origin/main`
`a689f4678e7fbb9ae89127df898295b2737e1920`. The contract is the higher level;
local text that contradicted it was amended to it. Catalog links with no local
home stay as names, not links; relinking belongs to Docs Propagation (T13).

## Directory Map

- [Test and Gate Contract](test-and-gate-contract.md) sets rules C1 to C24.
- [Test and Gate Contract Modules](test-and-gate-contract/README.md) hold the
  seven modules: registry, surfaces, scope, levels, corpus, floor, record.

## Adoption Status

| Module                      | Rules                   | Status  |
| --------------------------- | ----------------------- | ------- |
| 001 Registry and Dispatch   | C1 to C5                | adopted |
| 002 Surface Placement       | C6, C8 to C11           | adopted |
| 003 Pull-Request Scope      | C7                      | adopted |
| 004 Test Levels and Targets | C12, C14, C17, C18, C21 | adapted |
| 005 Behaviour Corpus        | C13                     | adopted |
| 006 Coverage Floor          | C15                     | adopted |
| 007 Conformance Record      | C16, C19, C20, C22-C24  | adapted |

004 is adapted: local target names now read `test:behaviour:coverage` (C14);
007 is adapted: the gate inventory and required-check record are completed in
T11/T13/T15, and diagram validation already runs at pull-request.
