# Product Requirements

## Stories

- As a maintainer, I can run common entry points automatically guarded and use one documented wrapper for other compute-bearing Nx targets.
- As a maintainer, I can distinguish capacity deferral, pressure shedding, task failure, and success.
- As a family member, I keep using routed Bnest while development work is controlled.

## Acceptance Criteria

### AC-01 — Safe admission

```gherkin
Scenario: Heavy development waits for safe capacity
  Given another guarded task owns the heavy-work lease or host pressure is unsafe
  When a compute-bearing Nx target starts through the guard
  Then the target waits for bounded safe admission
  And it exits temporarily unavailable if admission never becomes safe
```

### AC-02 — Owned shedding

```gherkin
Scenario: Sustained pressure sheds only guarded development
  Given a guarded ephemeral child is running
  When memory warning persists for ten seconds
  Then the guard terminates its child process group gracefully
  And production, Caddy, and unrelated processes receive no signal
```

### AC-03 — Service grace

```gherkin
Scenario: Development serve receives a longer warning window
  Given guarded development serve is running
  When memory warning persists for thirty seconds
  Then the development server is terminated gracefully
  And the routed production service remains ready
```

### AC-04 — Honest evidence

```gherkin
Scenario: Resource evidence uses supported meanings
  Given a guarded task or managed release is observed
  When the collector finalizes its summary
  Then CPU utilization is derived from cumulative CPU-time deltas
  And compressor payload is not reported as compressor fullness
  And old evidence is removed by bounded retention
```

### AC-05 — Shared repository rule

```gherkin
Scenario: Every coding harness reaches the resource rule
  Given repository rules and Nx task guidance are loaded
  When any supported harness runs compute-bearing Nx work
  Then it uses the canonical guarded target
  And it does not bypass a capacity deferral
```
