# Gate Inventory

This is the one table of every check this repository runs, as rule C19 of the
[Test and Gate Contract](checks/test-and-gate-contract.md) requires. Each row is a gate declared in `repo-config.yml`
under `gates.entries`. A gate on two surfaces has one row per surface. Hooks and workflows call a surface and copy no
command.

Scope follows rule C7. A commit or a changed file is checked as a changed unit. The quick gate is global in effect,
because it includes the static behaviour check.

| Gate                          | Surface        | Scope         | Command [6]                      | Tests            |
| ----------------------------- | -------------- | ------------- | -------------------------------- | ---------------- |
| `format-staged`               | `pre-commit`   | changed files | `prettier --write` [1]           | none             |
| `format-staged`               | `pull-request` | changed files | `prettier --write` [2]           | none             |
| `commit-message`              | `commit-msg`   | changed files | `check-commit-message.sh`        | none             |
| `commit-message`              | `pull-request` | changed files | `check-commit-message.sh` [3]    | none             |
| `public-safety-range`         | `pre-push`     | global        | `check.sh` over the pushed range | none             |
| `public-safety-range`         | `pull-request` | global        | `check.sh` over the review range | none             |
| `public-safety-tree`          | `pull-request` | global        | `check.sh` over the tree         | none             |
| `public-safety-tests`         | `pull-request` | global        | `public-safety/tests/run.sh`     | unit             |
| `remote-dispatch-refusal`     | `pull-request` | global        | check-remote-dispatch-refusal.sh | none             |
| `repo-config`                 | `pull-request` | global        | `repo-config validate`           | none             |
| `word-budget`                 | `pull-request` | global        | `word-budget validate` [4]       | none             |
| `directory-map`               | `pull-request` | global        | `directory-map validate` [4]     | none             |
| `quality-gates`               | `pull-request` | global        | `quality-gates validate` [4]     | none             |
| `harness-adapters`            | `pull-request` | global        | `harness adapters validate` [5]  | none             |
| `internal-links`              | `pull-request` | global        | `md internal-link validate`      | none             |
| `mermaid`                     | `pull-request` | global        | `md mermaid validate`            | none             |
| `markdownlint`                | `pull-request` | global        | `markdownlint-cli2`              | none             |
| `prettier-check`              | `pull-request` | global        | `prettier --check`               | none             |
| `format-elixir`               | `pull-request` | project       | `bnest-app` `format`             | none             |
| `commit-history`              | `pull-request` | changed files | `commitlint` over range          | none             |
| `behaviour-coverage`          | `pull-request` | global        | `behaviour coverage validate`    | none, static     |
| `hippo-bootstrap-test`        | `pull-request` | global        | `test-hippo-bootstrap.sh`        | integration      |
| `rhino-bootstrap-lint`        | `pull-request` | global        | `shellcheck` on the bootstrap    | none             |
| `rhino-consumer-repo`         | `pull-request` | global        | `rhino-consumer` `test:repo`     | none             |
| `test-quick-bnest-app`        | `pull-request` | project       | `bnest-app` `test:quick`         | unit plus static |
| `test-quick-bnest-app-be-e2e` | `pull-request` | project       | `bnest-app-be-e2e` `test:quick`  | unit plus static |
| `test-quick-bnest-app-fe-e2e` | `pull-request` | project       | `bnest-app-fe-e2e` `test:quick`  | unit plus static |
| `test-integration`            | `pull-request` | project       | `run-many` `test:integration`    | integration      |
| `test-e2e-be`                 | `scheduled`    | project       | `bnest-app-be-e2e` `test:e2e`    | e2e              |
| `test-e2e-fe`                 | `scheduled`    | project       | `bnest-app-fe-e2e` `test:e2e`    | e2e              |

1. Pre-commit: applies the formatting to the index.
2. Pull request: verify-clean replay after the write.
3. Over the explicit pull-request range.
4. The `governance` commands run as `./rhino governance <name> validate`.
5. Then the hook tests `.commandcode/hooks/policy-hooks.test.sh` and `.muse/hooks/run-policy-hook.test.sh`.
6. Command shows `<project> <target>`, which runs `npm exec --no -- nx run -p <project> -t <target>`. The `run-many` row
   runs `nx run-many -t <target>` in every project.

Each `./rhino <command>` in the registry is shown here without its prefix. The registry holds the full argv.

## Workflow-only checks

These run in the pull-request workflow, outside the registry, because their input is not a repository gate input.

- **Aggregate job `quality-gate`**, displayed as `Quality gate` (global): the single required result over every
  pull-request entry.
- **PR leak review** (not in CI): the judgement review that runs and passes before an agent push (C11).

## Exempt layers and infeasible checks

- **`rhino-consumer` has no `test:quick`.** The project owns the repository gate and has no unit level, so it has no
  `test:quick` (C14).
- **`bnest-app` has no `test:e2e`.** End-to-end proof lives in the two dedicated homes, `bnest-app-be-e2e` and
  `bnest-app-fe-e2e`.
- **`bnest-app-be-e2e` has no `test:integration`.** The backend e2e home owns no integration suite; integration proof
  for its corpus lives in `bnest-app:test:integration`.
- **E2E homes carry no numeric coverage.** Behaviour coverage is their only static gate; `test:unit` in those homes
  checks support code and carries no floor.
- **`test:live` is dev-only.** Its scenarios carry `ci-exempt`; the pull-request gate never runs it (C12).
- **Scenario exemptions.** A scenario may skip the integration or end-to-end level only with a reach reason in a
  `# Exemption(<level>)` comment. `behaviour coverage validate` checks each one. The unit level is never exempt.
- **Network denial.** `test:quick` does not run network-denied here. Hermeticity is enforced by the import and API ban
  scoped to unit-test paths and by the boundary-policy scan in `test:behaviour:verify`.
