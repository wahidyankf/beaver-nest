---
description: >-
  Points to the standing HIPPO-contention exception for a task-owned branch whose hosted PR quality gate mirrors the
  hook. Adopted from ose-rules at 2872299bd434c46ca4c57417079ca9c8fc3b4e54.
when_to_use: >-
  Use when the compute guard reports exit 124 with a never-started receipt for the pre-push hook and waiting for
  capacity would stall an otherwise ready task branch; read the canonical exception first.
---

# Capacity-Held Hook

[Back to Push-Hook Verification](../push-hook-verification.md#hippo-congestion-exception)

A hook held back by capacity has run nothing, so it holds no finding to fix. Retrying that same invocation once the
condition clears stays the default. This module states no second exception.

The one standing HIPPO-contention exception — when pushing a task-owned branch that lands through a pull request whose
quality gate mirrors the skipped hook's deterministic checks with `--no-verify` is sound and preferable, with its
manual screens, formatting, evidence, no-carry, direct-main-excluded, and no-merge-until-gate-passes conditions —
lives in [Push-Hook Verification](../push-hook-verification.md#hippo-congestion-exception).

## What This Never Covers

- A hook that ran and failed, however unrelated the failure looks. Fix the cause; a capacity receipt from an earlier
  attempt does not convert a failure into a deferral.
- Skipping a commit hook to land work locally where no hosted gate will ever see it.
- Weakening, muting, or removing any check, locally or hosted, to make room for this exception.
