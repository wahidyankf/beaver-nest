---
description: >-
  Defines the light, standard, and heavy HIPPO resource tiers and the honest tier choice that keeps local compute within
  its reservation.
when_to_use: >-
  Use when choosing the `--resource-tier` for a local HIPPO-guarded command, or when a run waited, was shed, or starved the
  queue.
---

# Tier Selection

A resource tier is a reservation, not a limit: HIPPO does not cap the process, so classify by what the work really
needs. `light` is one narrow static check (a linter, a formatter, one validator). `standard` is an ordinary check, one
project's tests, or a writer. `heavy` is a full build, a whole suite, or a quality gate.

A tier that is too low lets real use exceed the reservation: the host reaches pressure and HIPPO sheds ephemeral work. A
tier that is too high, or `heavy` by habit, holds capacity other runs need and starves the queue. Never choose a tier to
be admitted faster.

**Enforcement: unenforced by decision**, because what work really needs is a judgement no mechanical check can settle.
The boundary hook checks presence, not tier.
