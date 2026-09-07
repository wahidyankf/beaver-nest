# BeaverNest Cutover

BeaverNest becomes RHINO's first consumer and stops being Badakmini's host. The two halves happen in one change, because a repository running two validators of one contract is the condition this plan exists to remove.

## Consumer Bootstrap

The root `./rhino` script is a fork of the existing `./hippo` bootstrap, with `rhino.lock` beside it in the same `key=value` shape:

```text
version=v0.1.0
commit=<40 hex>
darwin-amd64=<sha256>
darwin-arm64=<sha256>
linux-amd64=<sha256>
linux-arm64=<sha256>
```

Forking 547 lines of shell is duplication, and it is the right call here for three reasons. HIPPO's own design already assumes it — "every consumer repository ships its own copy of this wrapper". The alternative of publishing the bootstrap as a RHINO release asset is circular: you need the script to fetch the release that contains the script. And a shared parameterized bootstrap would couple two independently released tools such that a change to one could break the other's installation path. This is a deliberate copy of a proven mechanism, not a missed abstraction, and it is recorded here so a later reader does not "fix" it.

The fork changes identifiers, the cache root (`~/Library/Caches/rhino` on Darwin, `${XDG_CACHE_HOME:-~/.cache}/rhino` on Linux), the release URL, and the executable name. Because the cache roots differ, the two tools never contend for one install guard, and RHINO's retention pass never sees a HIPPO release. The safety mechanisms are kept exactly as they are: lock-key uniqueness, exact version and 40-hex-commit shape validation, the supported platform matrix, warm-cache digest _and_ embedded-identity verification, `lockf`/`flock` install serialization, live-owner process-start identity checks, release claims that survive `exec`, and bounded retention that never evicts a release another repository is installing.

Its failure exits stay `78` for invalid configuration and `75` for contention, because those are the bootstrap's own outcomes as a HIPPO-family guard script. They are distinct from the `rhino` binary's `0`/`1`/`2` validator outcomes, and both appear in the consumer documentation so the distinction is never inferred.

## Consumer Specification and Suite

`specs/tools/rhino-consumer/` mirrors [the HIPPO consumer specification](../../../../specs/tools/hippo-consumer/README.md): it owns the bootstrap's observable behaviour and nothing about the executable, whose specification lives upstream. Its `behaviours/rhino-bootstrap.feature` is adapted from the HIPPO corpus, keeping the scenarios that describe fork-independent mechanics — tampered warm cache, malformed version, identity envelope mismatch, live and stale install-lock owners, crash recovery, bounded retention — and dropping nothing, because the forked mechanics are identical.

`.github/scripts/test-rhino-bootstrap.sh` implements it, mirroring the existing HIPPO bootstrap suite. It runs from the pre-push hook, gated on changes to the consumer boundary only, so an ordinary push pays nothing for it.

## Repository Gate Ownership

Badakmini's Nx project is the current home of `test:repo`, and roughly a dozen rules and documents name that target. Deleting the project without rehoming the target would break every one of those references.

A new `apps/rhino-consumer/` project takes ownership. It has a `project.json` and a `README.md` and no source: it composes `./rhino` invocations as Nx targets, exactly as Badakmini's `project.json` composes raw `dotnet` commands without an Nx language plugin. `apps/` rather than a new top-level `tools/` keeps it inside the existing `workspaces` glob and the existing project conventions; Badakmini also carried no `package.json`, so nothing new is required of npm. Its targets:

- `test:repo` — the eight validator invocations, run in parallel with prefixed output and a nonzero exit if any fails, with `cwd` at the workspace root. Same name, same semantics, same target path for every existing reference.
- `test:bootstrap` — the consumer bootstrap suite, so it is runnable outside the hook.

Its `inputs` mirror Badakmini's `test:repo` inputs, plus `rhino.lock` and `repo-config.yml`, so a pin move or policy edit correctly invalidates the cache.

## Pre-push Wiring

`.husky/pre-push` already routes three ways: the affected `test:quick` graph, the consumer-boundary suite, and the repository documentation gate. The cutover changes which paths trigger which:

- `validation_changes_for_range` drops `apps/badakmini-cli/**` and `apps/badakmini-cli-e2e/**` and gains `repo-config.yml` and `apps/rhino-consumer/**`. A policy edit must trigger the gate that enforces it.
- A second consumer predicate covers `rhino`, `rhino.lock`, `.github/scripts/test-rhino-bootstrap.sh`, and `specs/tools/rhino-consumer/**`, alongside the existing HIPPO one.
- The final gate command becomes the `apps/rhino-consumer:test:repo` target.

The hook moves from one gate to the other in a single edit. There is no commit at which neither validator gates a push.

### The other two hooks

`.husky/pre-commit` and `.husky/commit-msg` do not change. `lint-staged` already routes `yaml`/`yml` through Prettier, so `repo-config.yml` is formatted automatically with no configuration change; RHINO must therefore tolerate Prettier's YAML output, which it does, because Prettier reformats whitespace and quoting, not structure.

One addition is warranted. BeaverNest's `.prettierignore` and `lint-staged` config format no shell today, which is correct while every shell file in the tree is vendored — `./hippo` comes from upstream and is not ours to reformat. `./rhino` breaks that assumption: it is a 547-line security-critical script that this repository _owns and has modified_, holding the checksum verification, the install serialization, and the stale-owner reclamation. A `shellcheck` run over `rhino` and `.github/scripts/test-rhino-bootstrap.sh`, wired into the consumer-boundary predicate that already exists in pre-push, costs one line and covers the class of defect — an unquoted expansion, a mishandled exit status — that the bootstrap suite's scenario-level tests are not shaped to catch. Formatting is still not adopted, for the reason given in [the upstream design](01-rhino-repository.md); this is correctness, not style.

## Authority Cutover

Per the [plan-migrations convention](../../../../repo-governance/conventions/plan-migrations.md), an authority cutover is not proven by parity alone. The verification is:

1. Delete `apps/badakmini-cli/`, `apps/badakmini-cli-e2e/`, `specs/apps/badakmini/`, and `beaver-nest.sln`, so no fallback validator exists in the tree.
2. Clear the RHINO consumer cache, so the bootstrap performs a genuine cold download-and-verify rather than reusing a warm artifact from development.
3. Run the full repository gate as a freshly started process, reading policy only from the persisted `repo-config.yml` and the pinned release from `rhino.lock`.
4. Confirm it reports the same clean result across all five validators, over the same 49 word-budgeted files, four mapped trees, roughly 126 links, three-harness parity, and 25 Mermaid diagrams that Badakmini reported clean.
5. Confirm a deliberate injected violation of each kind is still detected, in a scratch copy under `local-tmp/`, so "clean" is proven to mean "checked" rather than "skipped".

Step 5 matters more than step 4. A validator that silently found nothing to check would pass step 4 perfectly.

## Residual Risk and the One Numeric Exception

The chosen proof strategy is the shared scenario corpus at unit, integration, and process levels. It does not include a byte-for-byte differential run of both binaries over this repository. The honest consequence: a behaviour that no scenario covers, and that the corpus rewrite did not surface, can change silently across the rewrite. The corpus is 81 scenarios over roughly 5,000 lines of F#, so this is a real gap, not a formality — it is accepted deliberately, and step 5 above is the compensating control.

One narrow exception is retained and is the subject of AC-06. The word budget is a counting gate: its output is an integer compared against a threshold, and a different Unicode word-boundary rule between .NET and Rust would move files across that threshold with no scenario failing. So before Badakmini is deleted, `md word-count inspect` is run under both binaries over every governed file and the counts must match exactly. This is one command per file over a known file set, not a general differential harness, and it is the only place where the retired binary is used as an oracle.

The same concern applies in principle to grapheme counting for Mermaid labels, where .NET text elements and UAX #29 could disagree on emoji or ZWJ sequences. That one is left to the corpus, because its gate compares against a limit that no governed diagram sits near, so a small counting difference cannot change an outcome.

## Rules and Documentation

Badakmini is named as the enforcement mechanism in roughly a dozen rule files. Renaming an enforcement reference is a rule change, so the [rules-propagation workflow](../../../../repo-governance/workflows/rules-propagation.md) applies and its terminal result is recorded — `PASS_NO_CHANGE` is a legitimate outcome only if the ledger genuinely closes empty, which it will not here.

Affected rules: `AGENTS.md`; `repo-governance/README.md`; the `directory-maps`, `markdown-links`, `markdown-visualizations`, `coding-harness-contract`, `push-hook-verification`, `documentation-architecture`, and `database-audit-columns` conventions; the `specification-maintenance`, `software-quality-enforcement`, and `end-to-end-testing` development standards; and the `coding-harness-contract-change`, `coding-harness-parity-verification`, `rules-propagation`, `rules-quality-gate`, and `plan-quality-gate` workflows.

Two changes are more than a rename. `coding-harness-contract.md` currently states the canonical roster as prose fact; after cutover the roster is declared in `repo-config.yml`, so the convention must point at the declaration as the source of truth while keeping the parity requirement itself canonical. And `directory-maps.md` states the 750-word budget as a rule constant; the constant remains a rule, but the enforcement sentence must name where the enforced value is declared. Neither loosens a rule; both stop the document from being a second, drifting copy of a value.

`plans/backlogs/family-learning-engine/delivery.md` names the retired target in four proof statements and is updated as an active plan. Archived plans under `plans/done/` are historical records and are not rewritten; link validation already excludes them as sources.

## Toolchain Removal

The cutover removes .NET from this repository entirely. `beaver-nest.sln` contains only Badakmini projects and two solution folders, so it is deleted rather than trimmed. `.github/workflows/scheduled-quality-gates.yml` loses the `badakmini-test-symphony` job and its `setup-dotnet` step. That job's exact contract — every integration suite, then the complete unfiltered E2E target, both kept out of `test:quick` and out of Git hooks — moves to RHINO's own `scheduled.yml`, so the boundary rule is preserved rather than dropped along with the job. `.gitignore` loses the Badakmini coverage path. `apps/bnest-app/tools/release.mjs` names `badakmini-cli` in its release gate list and is repointed at `rhino-consumer`.

## File Impact

New:

- `[N] rhino`, `rhino.lock`, `repo-config.yml` — pinned consumer bootstrap, release pin, declared policy.
- `[N] apps/rhino-consumer/project.json`, `apps/rhino-consumer/README.md` — repository gate ownership and its [project README](../../../../repo-governance/conventions/project-readmes.md).
- `[N] .github/scripts/test-rhino-bootstrap.sh` — consumer bootstrap suite.
- `[N] specs/tools/rhino-consumer/README.md`, `specs/tools/rhino-consumer/behaviours/README.md`, `specs/tools/rhino-consumer/behaviours/rhino-bootstrap.feature` — consumer specification and its maps.

Moved upstream, then deleted here:

- `[M] specs/apps/badakmini/cli/behaviours/*.feature` → RHINO `specs/behaviours/`, reworded for declared policy.
- `[M] specs/apps/badakmini/cli/architecture.md` → RHINO `specs/architecture.md`, rewritten for Rust containers.
- `[M] apps/badakmini-cli/{Governance,HarnessContract,Cli,Runtime,Program}.fs` → RHINO `src/` modules, rewritten in Rust.
- `[M] apps/badakmini-cli/tests/contract/{BehaviourSteps,BehaviourSupport}.fs` → RHINO `tests/support/`.

Deleted:

- `[D] apps/badakmini-cli/**`, `apps/badakmini-cli-e2e/**`, `specs/apps/badakmini/**`, `beaver-nest.sln`.

Edited:

- `[E] .husky/pre-push` — trigger paths, gate command, and a `shellcheck` run over the owned bootstrap fork.
- `[E] .github/workflows/scheduled-quality-gates.yml` — remove the Badakmini job and .NET setup.
- `[E] .gitignore`, `apps/bnest-app/tools/release.mjs`, `RTK.md`, `README.md` — target and path references.
- `[E] specs/apps/README.md`, `specs/tools/README.md` — directory maps.
- `[E] AGENTS.md`, `repo-governance/README.md`, and the fifteen rule files listed above — enforcement references.
- `[E] docs/reference/glossary.md`, `docs/how-to-guides/coding-harnesses.md` — tool identity and command.
- `[E] libs/ex-bdd/test/integration/ex_bdd/boundary_policy_test.exs` — a doc comment naming Badakmini as a boundary-guarding example.
- `[E] plans/backlogs/family-learning-engine/delivery.md` — four proof commands.
- `[E] plans/in-progress/README.md`, `plans/done/README.md` — stage maps at start and at archival.

Unknown at planning time: whether any `.agents/skills/**` resource names the retired target. A delivery task discovers this by exact search rather than assuming the earlier inventory was complete.

## Rollback

The trigger is any of: the repository gate failing after cutover for a reason not attributable to genuinely non-compliant content; a bootstrap that cannot verify the pinned release; or a governed file whose word count changed across the rewrite.

The action is to restore the deleted projects, `beaver-nest.sln`, and the previous `.husky/pre-push` from Git, and re-run the Badakmini gate. Nothing persistent is mutated by this plan, so restoring the tree is a complete rollback. A published RHINO tag is never edited or deleted in response; a defect becomes a new patch version and a new pin.
