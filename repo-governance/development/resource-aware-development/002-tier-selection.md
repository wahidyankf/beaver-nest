---
description: >-
  Defines the light, standard, and heavy HIPPO resource tiers, the optional very-heavy tier, the optional swap
  setting, and the honest tier choice that keeps local compute within its reservation.
when_to_use: >-
  Use when choosing the `--resource-tier` for a local HIPPO-guarded command, when a run waited, was shed, or
  starved the queue, or when declaring the very-heavy tier or swap counting in a machine file.
---

# Tier Selection

A resource tier is a reservation, not a limit: HIPPO does not cap the process, so classify by what the work really
needs. `light` is one narrow static check (a linter, a formatter, one validator). `standard` is an ordinary check, one
project's tests, or a writer. `heavy` is a full build, a whole suite, or a quality gate.

A tier that is too low lets real use exceed the reservation: the host reaches pressure and HIPPO sheds ephemeral work. A
tier that is too high, or `heavy` by habit, holds capacity other runs need and starves the queue. Never choose a tier to
be admitted faster.

Pick the smallest tier that fits, and move up only on measured need. Measure a run with
`./hippo history --since 30d --source beaver-nest`, whose rows carry `childCpuSeconds` and `childWallSeconds`.
Their ratio is the average CPU count the run kept busy. History records no memory, so measure peak memory with the
build tool or the operating system. A `pressure-shed` outcome shows a short host, not a larger need, so check the
host before moving up.

## Optional Settings

`very-heavy` is an optional last-resort tier. Declare it only in the schema-3 `hippo.local.json` of a machine
that can hold its maximum. A run that names it where the loaded file does not declare it exits `2` with
`hippo.args.invalid`.

`coordination.countSwap` is an optional schema-3 key, off by default, that counts unused swap as memory up to an
allowance. Enable it only on Linux, and never on zram-backed swap: zram is carved from RAM, so the same
memory would count twice. On macOS it changes nothing.

## Rollout

An older HIPPO binary refuses any file that declares either setting, so the whole file stops loading.
Declare a setting only after every checkout on that machine runs a HIPPO release that knows it:
repin each consumer, confirm each with `./hippo version --json`, and only then add the block or key.

## Enforcement

**Unenforced by decision**, because what work really needs is a judgement no mechanical check can settle.
The boundary hook checks presence, not tier.
