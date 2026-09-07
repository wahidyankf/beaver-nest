# Product Requirements

## Personas

- **Repository maintainer.** Works across five repositories with the same documentation standards. Wants one tool, one command shape, and one place to change a policy value. Does not want a language toolchain per repository.
- **Coding harness.** Runs the repository gate before reporting work complete. Needs a stable command, stable exit codes, and machine-readable findings.
- **Future consumer repository.** Has different trees, different word limits, and possibly a different harness roster. Needs to declare all of that rather than fork the tool.

## Stories

- As a maintainer, I run one command in BeaverNest and get exactly the findings Badakmini used to give me, without a .NET SDK installed.
- As a maintainer, I change the governed word limit or add a validated tree by editing `repo-config.yml`, and no tool release is required.
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
Scenario: Two repositories of different shape are both describable
  Given the rhino repository, which has no governance tree, no plans tree,
    and an empty coding-harness roster
  And the beaver-nest repository, which has all three
  When each is validated from its own declared configuration
  Then both are validated correctly by the same released binary
  And no default belonging to either repository is compiled into the tool
```

### AC-02 — Declared policy drives every validator

```gherkin
Scenario: Declared configuration selects what is enforced
  Given a repository configuration that declares governed surfaces, mapped trees,
    link exclusions, Mermaid label limits, and a harness registry
  When the word-budget, directory-map, links, mermaid, and harness-contract validators run
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

### AC-05 — Authority cutover with the prior validator unavailable

```gherkin
Scenario: RHINO is the only repository validator
  Given apps/badakmini-cli and apps/badakmini-cli-e2e have been removed from the repository
  When a freshly started rhino process runs the repository gate from the persisted configuration
  Then it validates word budgets, directory maps, internal links, Mermaid, and harness parity
  And the repository gate reports the same clean result the retired validator reported
  And no fallback to a previous validator is possible
```

### AC-06 — Word counts do not drift across the rewrite

```gherkin
Scenario: The numeric budget gate keeps its counts
  Given every Markdown file governed by the word budget in this repository
  When the retired validator and the released rhino binary each report a word count
  Then the two counts are identical for every governed file
```

### AC-07 — Rules and documentation tell the truth

```gherkin
Scenario: No rule or document names the retired validator
  Given the repository rules, documentation, specifications, targets, and hooks
  When the cutover is complete
  Then every enforcement reference names the rhino command or target
  And the rules-propagation workflow has recorded a terminal result for the rule change
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

### AC-09 — The household service is undisturbed

```gherkin
Scenario: Tooling work does not touch the routed service
  Given the routed BeaverNest origin is healthy before this work begins
  When the extraction, cutover, and retirement are complete
  Then the routed origin serves the same revision and remains healthy
  And no deployment, candidate, or route change was required
```

## Scope

In scope: the upstream Rust repository, its specification corpus, its documentation tree, its release pipeline, the configuration schema, the BeaverNest bootstrap and lock, the consumer specification, the Nx target and hook wiring, retirement of both Badakmini projects, and every rule, document, specification, and map that names them.

Out of scope: adoption by the four sibling repositories, any merge with `ose-public`'s `apps/rhino-cli`, new validators, new output formats, and any change to governed content or to BeaverNest's product, storage, or deployment.

## Risks

- The corpus-only proof strategy accepts that a semantic gap no scenario covers can survive the rewrite; AC-06 narrows this for the one gate whose output is a number.
- Aligning to `ose-public`'s configuration shape imports a schema decision made for a different repository; the alignment is deliberate and recorded, but a future divergence is possible.
- The upstream release pipeline depends on hosted macOS runners, whose availability and cost profile are outside this repository's control.
