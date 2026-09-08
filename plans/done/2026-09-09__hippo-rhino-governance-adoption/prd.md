# Product Requirements

## Personas

- **The maintainer at full attention.** Making a deliberate change to one CLI. Wants to find the rule that governs it in one hop from `AGENTS.md`, see which level it sits at, and know what supersedes it. Today they get a flat list and have to remember which bullets are load-bearing.
- **The maintainer at low attention.** Finishing something at the end of a day, on `main`, with commit rights and no objection from the server. This is the persona the ruleset exists for. Nothing this plan builds should depend on this person remembering anything.
- **A coding harness.** Claude Code, Codex, or OpenCode, opened in either repository. Needs the same rules, the same skills, the same agent, and the same permission boundaries as the other two, expressed in its own native syntax without any of the three receiving an extra always-on instruction.
- **A future contributor or a future self.** Opens a pull request from a checkout whose hooks never ran, or from the GitHub web editor. Must be refused by the server for exactly the reasons the hooks would have refused locally.
- **RHINO the tool, reading its own repository.** The first non-BeaverNest tree to exercise the harness-parity engine against a non-empty roster. A shape it cannot express is a defect this plan must surface before HIPPO depends on it.

## Stories

- As a maintainer, I open `AGENTS.md` in either CLI, follow one link, and reach the rule that governs what I am about to do — and when two rules disagree, the hierarchy tells me which wins instead of leaving me to decide.
- As a maintainer, I find the procedure I am about to perform written down as a workflow: how to take a change from worktree to merged pull request, how to change the harness contract, how to verify parity, how to review a Gherkin implementation, how to cut a release in this specific repository.
- As a maintainer, I cannot push to `main` in either repository, from any checkout, using any credential I hold — and I learn this from the server refusing me, not from a document asking me not to.
- As a maintainer, I open a pull request and one check decides whether it can merge, and that check runs everything the old CI ran plus everything the hooks enforce.
- As a maintainer, I create a worktree in either repository, run every gate, and get exactly the results I got before the worktree existed.
- As a maintainer, I know which rules in these two repositories came from BeaverNest and that nothing keeps them in sync, because the tree says so — so I read a difference as a decision rather than as rot.
- As a coding harness, I read one always-on instruction body, reach every canonical skill and the canonical agent through my own adapter, and find no second instruction source hiding in my vendor settings file.
- As a maintainer, I look at any of the three repositories and see the same worktree and branch name for this work, so I never have to reconstruct where the adoption got to.
- As RHINO, I validate my own repository from a source build with a non-empty harness roster and report either a clean tree or a defect in myself, before HIPPO pins anything that depends on the answer.

## Acceptance Criteria

### AC-01 — Governance is extracted, with a recorded verdict per document

```gherkin
Scenario: Every source document has a recorded adoption verdict
  Given the governance corpus of the beaver-nest repository
  When the adoption matrix for a target repository is complete
  Then every source document carries adopt, adopt-adapted, or reject
  And every verdict states the reason it was reached
  And no adopted document names a service, database, browser, or workspace tool absent from that repository
```

```gherkin
Scenario: No existing rule is lost in the restructure
  Given the enumerated rule inventory of a target repository's current instruction file
  When that repository's governance hierarchy is in place
  Then every enumerated rule maps to exactly one destination document
  And any rule without a destination blocks the phase until it has one
```

### AC-02 — The instruction file becomes an index and the hierarchy is navigable

```gherkin
Scenario: The instruction file holds links rather than rules
  Given a target repository with its governance hierarchy in place
  When its root instruction file is read
  Then it contains navigation to the governance tree and no rule stated only there
  And it is within that repository's declared word budget
```

```gherkin
Scenario: Every governance directory is mapped and every link resolves
  Given a target repository with its governance hierarchy in place
  When that repository's own documentation gate runs
  Then every directory under the governance tree has a README with a complete directory map
  And every internal Markdown link resolves inside the repository
  And every governed document is within the declared word budget
```

### AC-03 — Workflows are populated and executable

```gherkin
Scenario: The workflow level carries the procedures a maintainer repeats
  Given a target repository with its governance hierarchy in place
  When the workflow level is listed
  Then it contains worktree-to-pull-request, harness-contract change, harness-parity verification
  And it contains Gherkin-implementation review, red-green-refactor, and rules propagation
  And it contains that repository's own release-cut procedure with its real commands
```

```gherkin
Scenario: A workflow names commands that exist in that repository
  Given any workflow document in a target repository
  When each command it names is run against that repository
  Then every command resolves and no command names a tool that repository does not have
```

### AC-04 — Worktrees live in the repository and change no result

```gherkin
Scenario: A worktree is present and every gate reports identically
  Given a target repository with a recorded set of gate results on a clean tree
  When a worktree is created at the in-repository worktree path
  And every gate is run again from the primary checkout
  Then each gate reports the result it reported before the worktree existed
  And no gate reads a file inside the worktree
```

```gherkin
Scenario: A worktree never enters history
  Given a target repository with a worktree present
  When the working tree status is inspected
  Then only the placeholder inside the worktree tree is tracked
  And the worktree contents are ignored
```

### AC-05 — One merge-blocking gate, a superset of the hooks

```gherkin
Scenario: The gate refuses what each local hook refuses
  Given a pull request whose commits violate the conventional-commit contract
  When the pull-request quality gate runs
  Then the aggregate check fails
  And the same holds for unformatted staged content and for a failing quick suite
```

```gherkin
Scenario: The gate keeps every check the retired workflow ran
  Given the check inventory of a target repository's continuous-integration workflow before this change
  When the pull-request quality gate is in place and that workflow is deleted
  Then every inventoried check runs inside the gate
  And no check is left running only on a schedule that used to block merge
```

```gherkin
Scenario: A skipped job cannot open the merge button
  Given a pull request where a conditional gate job is skipped
  When the aggregate check evaluates its dependencies
  Then a skipped or cancelled dependency is not treated as success
```

### AC-06 — Main refuses everybody

```gherkin
Scenario: A direct push to the default branch is refused
  Given a target repository whose default-branch ruleset is in place
  When the owner pushes a commit directly to the default branch
  Then the push is refused by the server
  And the refusal is recorded as evidence
```

```gherkin
Scenario: The required check is a name the server has actually seen
  Given a pull request that has completed a full gate run
  When the ruleset's required status check is configured
  Then the required name is taken from that observed run
  And a subsequent pull request reaches a mergeable state once the gate passes
```

```gherkin
Scenario: No actor holds a bypass
  Given a target repository whose default-branch ruleset is in place
  When the ruleset's bypass actors are read
  Then the list is empty
  And force push and branch deletion are refused for every actor
```

### AC-07 — Three harnesses, no Nx, no MCP server

```gherkin
Scenario: The harness contract is declared without a capability server
  Given a target repository declaring three coding harnesses
  When its repository configuration is validated
  Then the configuration is accepted with no required capability server declared
  And no canonical skill or agent names a workspace task runner that repository does not use
```

```gherkin
Scenario: Every canonical document is reachable from every harness
  Given a target repository with canonical skills and a canonical agent
  When harness parity is reconciled
  Then each canonical document has an adapter for every harness that expresses it
  And no adapter copies, extends, or weakens the canonical content
```

```gherkin
Scenario: A competing instruction source is refused wherever it hides
  Given a target repository with its harness contract in place
  When a second always-on instruction is added as a file or as a vendor settings field
  Then the parity check reports it
  And an empty or absent settings field is reported as an answer rather than a violation
```

### AC-08 — The workflow is exercised before it is required

```gherkin
Scenario: Every change lands through the path it establishes
  Given any change this plan makes to a target repository
  When that change reaches the default branch
  Then it arrived through a pull request from the shared worktree branch
  And the branch and its worktree were removed afterwards
```

```gherkin
Scenario: One name identifies this work everywhere
  Given the three repositories this plan touches
  When each is inspected while the work is active
  Then each carries the same worktree directory name and the same branch name
```

### AC-09 — Nothing the repositories already had is weakened

```gherkin
Scenario: Product contracts survive the restructure unchanged
  Given each target repository's existing rules on exit codes, coverage floors, release immutability and specification discipline
  When the governance hierarchy is in place
  Then each of those rules is stated in the hierarchy with its original force
  And no threshold, prohibition, or exemption boundary is relaxed
```

```gherkin
Scenario: A budget conflict is resolved by splitting, never by raising
  Given an adopted document that exceeds the repository's declared word budget
  When the conflict is resolved
  Then the document is divided into coherent documents that each comply
  And the declared budget is unchanged and no substance is dropped
```

## Scope

In scope: the governance hierarchy and its adoption matrix in both repositories; the `workflows/` level including two newly authored workflows; the in-repository worktree tree and its exclusions; the three-harness contract with authored canonical skills and one canonical agent; `repo-config.yml` changes covering word budget, mapped trees, Mermaid palette, harness parity and scan exclusions; one pull-request quality gate per repository and the deletion of the workflow it replaces; the default-branch ruleset in both repositories; and the retirement of the external worktree directory.

Out of scope: everything listed under non-goals in [the business requirements](brd.md), and any change to either CLI's behaviour, command surface, exit codes, release artifacts, or coverage floors.

## Risks

- The restructure is the largest documentation change either repository has taken, and its failure mode is silent: a rule that quietly stops being stated. AC-01's inventory mapping exists because reading the result cannot detect that.
- The gate is authored twice, once per repository, against two different toolchains. The temptation is to make them look alike rather than make each correct; the acceptance criteria are written against each repository's own inventory for that reason.
- A ruleset with no bypass is only as good as the gate's reliability. The plan accepts a slower recovery path in exchange for an enforcement rule that has no exceptions to reason about.
