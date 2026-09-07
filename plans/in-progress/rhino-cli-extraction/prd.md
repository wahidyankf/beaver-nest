# Product Requirements

## Personas

- **Repository maintainer.** Works across five repositories with the same documentation standards. Wants one tool, one command shape, and one place to change a policy value. Does not want a language toolchain per repository.
- **Coding harness.** Runs the repository gate before reporting work complete. Needs a stable command, stable exit codes, and machine-readable findings.
- **Sibling repository.** HIPPO has no instruction adapter and no harness roster; grind-in-public has four mapped trees and its own Go validator to retire. Both need to declare their shape rather than fork the tool — which is what they did last time.

## Stories

- As a maintainer, I run one command in any of four repositories and get the findings that repository's own validator used to give me — without a .NET SDK in BeaverNest or a Go toolchain in grind-in-public.
- As a maintainer, I change the governed word limit or add a validated tree by editing `repo-config.yml`, and no tool release is required.
- As a maintainer, I can see what the rewrite actually bought me — gate time, memory, and setup cost, before and after — rather than taking it on faith.
- As a maintainer, I pin a RHINO version, commit, and checksum, and a tampered or substituted binary never runs.
- As a maintainer, I move the pin forward deliberately, and I can move it back by restoring the previous lock.
- As a coding harness, I get `0` for clean, `1` for findings, and `2` for a bad invocation or bad configuration, and `--output json` when I need to reason about findings.
- As a future consumer repository, I adopt RHINO by writing `repo-config.yml` and a lock file, without patching the tool — and I can read RHINO's own configuration as a worked example of a repository unlike BeaverNest.

## Acceptance Criteria

### AC-01 — The tool owns no repository's policy

```gherkin
Scenario: A repository without declared policy is refused
  Given a repository tree that contains no rhino repository configuration
  When any rhino validate command runs against that repository root
  Then it reports missing configuration and exits with the invocation error code
  And it applies no built-in tree, word limit, harness, or canonical path
```

```gherkin
Scenario: Four repositories of different shape are all describable
  Given the rhino repository, which declares an empty coding-harness roster
  And the hippo repository, which declares no instruction adapter at all
  And the grind-in-public repository, which declares four mapped trees
  And the beaver-nest repository, which declares four trees and three harnesses
  When each is validated from its own declared configuration
  Then all four are validated correctly by the same released binary
  And no default belonging to any of them is compiled into the tool
```

### AC-02 — Declared policy drives every validator

```gherkin
Scenario: Declared configuration selects what is enforced
  Given a repository configuration that declares governed surfaces, mapped trees,
    link exclusions, Mermaid label limits, and a harness registry
  When the word-budget, directory-map, internal-link, mermaid, and harness-parity validators run
  Then each validator enforces exactly the declared values
  And changing a declared value changes the findings without changing the tool
```

### AC-03 — One corpus, three adapters

```gherkin
Scenario: Every specified scenario is bound at every applicable level
  Given the rhino behaviour corpus under its specifications tree
  When the static behaviour-coverage check runs
  Then every scenario has exactly one substantive unit binding
  And every scenario has an integration and process binding or a valid documented exemption
  And no binding is unused, ambiguous, or a placeholder
```

### AC-04 — Pinned consumption fails closed

```gherkin
Scenario: Only the pinned, verified release executes
  Given a lock that pins a release version, source commit, and per-platform checksum
  When the rhino consumer bootstrap runs
  Then it executes the release only after the archive checksum and the executable's
    embedded release identity both match the lock
  And a mismatched, tampered, or cached-but-wrong payload is rejected before it executes
```

### AC-05 — Authority cutover with each prior validator unavailable

```gherkin
Scenario: RHINO is the only general-hygiene validator in each repository
  Given the prior validator has been removed from beaver-nest and from grind-in-public
  When a freshly started rhino process runs each repository gate from its persisted configuration
  Then it validates word budgets, directory maps, internal links, Mermaid, and harness parity
  And each gate reports the same clean result that repository's retired validator reported
  And no fallback to a previous validator is possible in either repository
  And every repository-specific check that rhino does not own still runs unchanged
```

### AC-06 — Word counts do not drift across the rewrite

```gherkin
Scenario: The numeric budget gate keeps its counts
  Given every Markdown file governed by the word budget in a repository being cut over
  When the retired validator and the released rhino binary each report a word count
  Then the two counts are identical for every governed file
  And this holds for beaver-nest and for grind-in-public independently
```

### AC-07 — Rules and documentation tell the truth

```gherkin
Scenario: No rule or document names the retired validator
  Given the rules, documentation, specifications, targets, and hooks of a
    repository that has cut over
  When the cutover is complete
  Then every enforcement reference names the rhino command or target
  And that repository's own rules-propagation workflow has recorded a terminal
    result for the rule change
  And this holds independently for beaver-nest and for grind-in-public
  And hippo runs no such transaction, because adoption there changes no rule
```

### AC-08 — Portable, immutable releases

```gherkin
Scenario: A tagged release publishes verifiable artifacts
  Given a version tag pushed on the upstream main branch
  When the release workflow runs
  Then it publishes archives for darwin and linux on amd64 and arm64 with a checksums file
  And each executable reports the tagged version and its source commit
  And an existing release tag is never replaced
```

### AC-09 — The household service is undisturbed

```gherkin
Scenario: Tooling work does not touch the routed service
  Given the routed BeaverNest origin is healthy before this work begins
  When the extraction, cutover, and retirement are complete
  Then the routed origin serves the same revision and remains healthy
  And no deployment, candidate, or route change was required
```

### AC-10 — Documentation is true, navigable, and self-checked

```gherkin
Scenario: The upstream repository passes its own checks on every push
  Given rhino ships a repository configuration describing its own trees
  When CI runs the freshly built binary against the rhino repository
  Then directory maps, internal links, Mermaid accessibility, and the word budget all pass
  And a deliberately broken link or over-budget instruction file fails that build
```

```gherkin
Scenario: Every published command was actually run
  Given the documentation tree following Diataxis with four categories
  When a reviewer checks each page against the shipped binary
  Then every page belongs to exactly one category
  And every command and transcript shown was executed against the current build
  And no page contradicts the canonical specification corpus
```

### AC-11 — Additive adoption regresses nothing

```gherkin
Scenario: A repository with no prior validator adopts cleanly
  Given hippo has no repository-hygiene validator and no configuration
  When it adopts the pinned rhino release with its own declared policy
  Then its documentation, specification, and instruction trees validate
  And every gate hippo already had continues to pass unchanged
  And nothing is removed from that repository
```

### AC-12 — The change is measured, not assumed

```gherkin
Scenario: Before-and-after evidence exists for every cutover
  Given a baseline captured before any change, for both retired validators
  When each cutover completes
  Then gate wall-clock, startup, peak memory, toolchain acquisition, and
    repository footprint are recorded for before and after
  And the distribution path is measured end to end — artifact size per platform,
    cold pin-to-executable, warm resolution overhead, and cache footprint
  And the warm gate is no slower and peak memory no higher than its baseline
  And warm resolution overhead is small enough to disappear into a gate run
  And any metric that got worse is reported as prominently as one that improved
```

## Scope

In scope: the upstream Rust repository, its specification corpus, its documentation tree, its release pipeline, and the configuration schema; adoption in four repositories — rhino, BeaverNest, HIPPO, and grind-in-public — including each one's bootstrap, lock, declared policy, gate wiring, and hooks; retirement of BeaverNest's F# Badakmini and grind-in-public's Go `badak-mini`; and every rule, document, specification, and map in either repository that names them.

Out of scope: `ose-public` and `ose-private` adoption, any merge with `ose-public`'s `apps/rhino-cli`, grind-in-public's repository-specific Node and spelling checks, new validators, new output formats, and any change to governed content or to BeaverNest's product, storage, or deployment.

## Risks

- The corpus-only proof strategy accepts that a semantic gap no scenario covers can survive the rewrite; AC-06 narrows this for the one gate whose output is a number.
- Aligning to `ose-public`'s configuration shape imports a schema decision made for a different repository; the alignment is deliberate and recorded, but a future divergence is possible.
- The upstream release pipeline depends on hosted macOS runners, whose availability and cost profile are outside this repository's control.
- grind-in-public's validator was written independently rather than copied, so its behaviour may differ from Badakmini's in ways no scenario predicts. Its findings are reconciled last, when three repositories of evidence already exist, and a disagreement is investigated rather than assumed to be a RHINO defect.
- Two repositories retire a working validator in one plan. Each rollback is independent and restores only its own tree.
