# Benchmarks

This plan replaces a .NET application and a Go binary with a Rust one. "Faster and cheaper" is the intuition behind that choice; this document turns it into a measurement, taken before anything changes and again after each cutover.

The point is not to celebrate a number. It is to know whether the change actually paid, and to catch the case where it did not — a rewrite that is slower or heavier than what it replaced is a finding, not a footnote.

## What Is Measured

| Metric                        | Why it is the one that matters                                                                                                                                           | Instrument                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **Gate wall-clock, warm**     | The felt cost. Every push runs this, so seconds here are the whole user-visible benefit.                                                                                 | Median of 7 runs of the full repository gate with the Nx cache skipped.                                                                     |
| **Gate wall-clock, cold**     | What CI and a fresh checkout actually pay, including any build step.                                                                                                     | One run from a clean build output and a cleared tool cache.                                                                                 |
| **Single-validator startup**  | The .NET-versus-native difference concentrates here, and it multiplies across the eight invocations the gate makes.                                                      | Median of 20 runs of the cheapest leaf against a fixture with no findings.                                                                  |
| **Peak resident memory**      | Determines whether the gate competes with the rest of the machine under HIPPO.                                                                                           | `/usr/bin/time -l` maximum resident set size on the full gate.                                                                              |
| **Toolchain acquisition**     | The cost nobody counts: what a clean machine or CI runner spends before the first check runs.                                                                            | Wall-clock for the prerequisite step — .NET SDK install plus restore and build, against a pinned-binary download and checksum verification. |
| **Distributed artifact size** | Every consumer downloads and caches this per platform. Already a release gate; recorded here so it sits with the rest.                                                   | Stripped size of each of the four release executables, and of the archive actually downloaded.                                              |
| **Cold bootstrap**            | What a fresh clone or CI runner pays once: resolve the pin, download, verify checksums, install. This is the toolchain acquisition cost the plan claims to have removed. | Wall-clock for the first `./rhino` invocation from an empty cache, on a stated network.                                                     |
| **Warm resolution overhead**  | Paid on _every_ invocation forever. A bootstrap that re-verifies expensively would quietly eat the startup win.                                                          | Difference between `./rhino version` through the bootstrap and the cached executable invoked directly, median of 20.                        |
| **Consumer cache footprint**  | Four repositories will each hold a RHINO cache next to a HIPPO one.                                                                                                      | On-disk size of the cache root after install and after bounded retention has run.                                                           |
| **Repository footprint**      | The maintenance surface that disappears.                                                                                                                                 | Tracked lines and files removed from each cutover repository.                                                                               |

### The Distribution End Result

Artifact size is the metric everyone quotes, and it is the least interesting one. What a consumer actually experiences is the whole path from a pinned lock line to a running check, so that path is measured end to end rather than at its most flattering point:

| Stage                     | Measured as                                            | What a bad number would mean                                                                                     |
| ------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| Pin to executable, cold   | Empty cache to first successful `rhino version --json` | The download-and-verify design is heavier than installing an SDK, which would undo the toolchain claim outright. |
| Pin to executable, warm   | Repeat invocation with the cache populated             | Verification is being redone per call instead of amortised.                                                      |
| Executable to verdict     | The gate itself, already measured above                | The rewrite did not deliver.                                                                                     |
| Steady-state cost on disk | Cache root after retention                             | Bounded retention is not actually bounding anything.                                                             |

The two bootstrap figures are the ones with no equivalent in the baseline: Badakmini had no distribution step, because it was built from source in the same tree. That asymmetry is stated rather than hidden — the honest comparison is _SDK install plus restore plus build_ against _download plus verify_, and both sides of it are recorded with their network and cache conditions, since a fast download on a good connection is not evidence about a slow one.

Nothing is measured that the plan cannot act on. Throughput on synthetic corpora, micro-benchmarks of individual functions, and allocation counts are all excluded: they would be work without a decision attached.

## Method

Fairness matters more than precision here, because the comparison crosses a language boundary and is easy to make meaningless.

- **Same machine, same tree, same session.** Before and after are measured on the same host against the same repository revision wherever the revision has not changed; where cutover changed the tree, the diff is stated alongside the number.
- **Guarded.** Every timed run goes through `./hippo run --class ephemeral`, so host contention does not silently skew a result. A capacity deferral invalidates the sample; it is re-run, not recorded.
- **Caches stated, never assumed.** Nx caching is skipped for every timed gate run. Cold runs clear the build output and the RHINO consumer cache explicitly, and say so.
- **Median of repeats, with the range.** A single timing is noise. Report the median and the observed minimum and maximum; a range wider than the difference being claimed means the claim is not supported.
- **Warm-up discarded.** .NET JIT and filesystem cache both penalise a first run. Discard the first two runs of each warm series so the comparison measures steady state rather than start-up luck.
- **No cherry-picking.** Every metric in the table above is recorded for both sides, including any that got worse.

Numbers are recorded in `learnings.md` with their date, host state, and command, so a later reader can tell whether a result is still meaningful or was taken on a machine that no longer exists.

## Baseline, Before Anything Changes

The baseline is captured in Phase 1, before a line is written, for two reasons. The obvious one is that a baseline taken after the work has begun is contaminated. The less obvious one is that both retired validators stop existing at cutover; measuring them afterwards means checking out old revisions and rebuilding toolchains that were deliberately removed.

Two baselines are needed, because two implementations are being replaced:

- **BeaverNest** — `apps/badakmini-cli`, F# on .NET 10, invoked as eight `dotnet` commands over one build.
- **grind-in-public** — `apps/badakmini-cli`, Go, invoked as three `badak-mini` commands.

The Go baseline is the more demanding comparison and the more interesting one. Go and Rust are both natively compiled with fast startup, so a large win there is unlikely and is not claimed; what a shared tool buys grind-in-public is one implementation instead of its own, not raw speed. Saying that up front stops the benchmark from being read as a promise it was never going to keep.

## Regression Thresholds

The measurement is not decorative — three of these gate the plan, and the rest are recorded.

- **The warm gate must not get slower.** If RHINO's median warm gate exceeds the baseline median in either cutover repository, that is a blocking finding: investigate and fix before retirement, or record an explicit, justified acceptance with the maintainer. It never passes silently.
- **Peak memory must not exceed the baseline.** Same handling. The gate runs under HIPPO alongside other work, so regression here has a cost beyond this repository.
- **Artifact size stays within its declared ceiling**, which the release pipeline already enforces.
- **Warm resolution overhead must stay small enough to disappear into the gate.** If the bootstrap's per-invocation cost is a material fraction of a validator run, the caching design is wrong and is fixed before the cutovers, not after. Cold bootstrap is recorded but not gated, because it is paid once and depends on a network the plan does not control.
- Startup, toolchain acquisition, and footprint are **recorded but not gated.** They are expected to improve substantially, and an improvement that fails to appear is worth understanding — but none of them is a reason to block a cutover on its own.

A metric that gets worse is reported in the delivery record with the same prominence as one that improves.

## Where the Results Live

Raw numbers and their conditions go in `learnings.md` as they are taken. The final reconciliation in Phase 11 assembles one before-and-after table covering both cutover repositories, every metric above, and the distribution figures for all four platforms, so the plan closes with the evidence in one place rather than scattered across dated entries.

If the numbers turn out to be uninteresting — comparable performance, with the real win being one tool instead of three — that is the honest result and is recorded as such. The case for this plan does not rest on the benchmark.
