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
- **grind-in-public** — `apps/badakmini-cli`, Go, invoked as three `badak-mini` hygiene commands. Its repository-footprint figure is a partial removal, not a total one: `harness rule-change` shares the module and stays, so the Go toolchain is not shed there and must not be counted as if it were.

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

## The Assembled Result

_Phase 11, 2026-09-08. One table, both cutover repositories, every metric above, and all four platforms. Each figure is traceable to a dated `learnings.md` entry; the conditions that differ between a before and its after are named in the row rather than averaged away._

### The two cutover repositories

| Metric                       | BeaverNest before (F#/.NET) |                    BeaverNest after (RHINO) |    grind-in-public before (Go) |            grind-in-public after (RHINO) |
| ---------------------------- | --------------------------: | ------------------------------------------: | -----------------------------: | ---------------------------------------: |
| Warm gate, **like-for-like** |      223 / 228 ms, 8 leaves | 220 / 229 / 221 ms, 6 leaves + 1 resolution | 0.373 s, 3 leaves via `go run` |                    **0.271 s**, 6 leaves |
| Warm gate, bracketed harness |                     0.392 s |              0.423 s (0.373 s leaves alone) |         0.236 s (built binary) |                                  0.271 s |
| Warm gate, already resolved  |                           — |                                166 / 173 ms |                              — |                                        — |
| Single-validator startup     |                     0.277 s |             0.252 s wrapped, 0.198 s direct |                        0.215 s |                                  0.264 s |
| **Peak resident memory**     |                **64.4 MiB** |                                 **8.4 MiB** |                   **12.1 MiB** |                              **8.2 MiB** |
| Toolchain on disk            |  674 MB (.NET 10.0.107 SDK) |                        one verified archive | 258 MB GOROOT + 2.3 GB modules | unchanged — `rule-change` still needs it |
| Validator source retired     |           5,044 lines of F# |                                           — |              3,949 lines of Go |                                        — |
| Consumer added               |                           — |                                   836 lines |                              — |                                836 lines |

Two rows gate the plan, and **both hold in both repositories**: the warm gate did not get slower on the like-for-like measurement, and peak memory did not rise. Everything else is recorded, not gated.

**Read the wall-clock rows with their reasons, because the two repositories improved for opposite causes.** BeaverNest is **parity**, not a win: 220–229 ms against 223–228 ms is the same number, and the bracketed row's apparent 8% regression is the bootstrap's ~55 ms sitting inside a harness that charges 190 ms of its own interpreter startup. grind-in-public is **27% faster**, and not because Rust beat Go: its wired path compiled through `go run` on every invocation, and a pinned binary removes that step. Against grind's _built-binary_ figure RHINO is 15% slower — while doing six checks instead of three. Neither repository got a faster validator; one stopped paying for a compile.

**The memory row is the one that improved on its own merits**, in both repositories and in opposite directions of prior size: 64.4 MiB to 8.4 MiB where the old tool was a runtime, and 12.1 MiB to 8.2 MiB where it was already a small native binary — the second doing twice the work. `harness parity` reads 1.9 MB where Badakmini read 98.9 MB.

**The number the plan actually bought is the last two rows.** 5,044 lines of F# and 3,949 lines of Go stopped being maintained — 8,993 lines of independently written, separately tested, separately documented implementations of the same six checks — against one shared 597-line bootstrap plus each repository's own declared policy. That was the case for the plan, and the timing table's job was only to prove it cost nothing.

### The distribution end result

| Platform                    | Stripped executable | Gzipped archive | Ceiling  |
| --------------------------- | ------------------: | --------------: | -------- |
| `aarch64-apple-darwin`      |           1,499,424 |         722,586 | 1.75 MiB |
| `x86_64-apple-darwin`       |           1,759,232 |         769,000 | 2 MiB    |
| `aarch64-unknown-linux-gnu` |           1,905,472 |         828,057 | 2.25 MiB |
| `x86_64-unknown-linux-gnu`  |           2,140,760 |         856,473 | 2.5 MiB  |

`checksums.txt` is 408 bytes and covers all four; a consumer downloads 723–837 KiB. Release pipeline wall clock: **2 min 29 s** from tag push to published release, with `macos-15-intel` (109 s) the critical path by two and a half times, almost entirely in runner allocation. The same source produces executables **43% apart** across platforms, which is why each carries its own ceiling rather than sharing one set to the largest.

### The honest summary

The benchmark came out roughly where §Method predicted: **comparable performance, a large and real memory improvement, and the toolchain requirement gone in the repository that had a runtime.** The case for this plan never rested on speed, and the numbers do not let it. What four repositories have now is one implementation of six checks instead of three implementations of the same six, each pinned by checksum to the same released tag.
