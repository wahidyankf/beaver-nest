# GitHub Actions Storage

## Purpose

Keep GitHub Actions storage within repository and owner allowances without paid overage. This
standard applies to workflow contributors and repository or owner administrators.

## Standards

### Workflow artifacts

- Every `actions/upload-artifact` step must declare `retention-days`.
- Use `retention-days: 1` when an artifact only transfers data between jobs in one workflow run.
- Use at most `retention-days: 7` for an artifact retained for failure triage.
- A value above 7 requires a non-empty YAML comment immediately above `retention-days`. The comment
  must name the operational need, the accountable owner, and the removal or review condition. This
  exception does not authorize an administrator to raise the repository retention setting.
- Do not upload cheaply reproducible outputs.
- Keep repository artifact/log retention at or below 7 days as a backstop; explicit per-upload
  retention remains the primary control.

A workflow passes when each upload has an allowed value and any value above 7 has the required
exception. A missing value, an unexplained value above 7, or an upload without a consumer violates
this standard.

### Packages and the owner allowance

Treat 500 MB as the owner-wide planning ceiling shared by Actions artifacts and GitHub Packages.
Do not depend on repository visibility or current free-product treatment when deciding whether a
workflow remains safe if the repository later becomes private.

Every GitHub Package publisher must link to or contain both:

- a lifecycle rule that names which versions remain, how obsolete versions are deleted, and who
  owns cleanup; and
- a steady-state estimate reconciled with the owner's existing artifact and Packages usage.

Calculate the repository estimate as:

```text
artifact MB = uploads per day * retained days * average compressed MB per upload
package MB = retained package versions * average compressed MB per version
owner projection MB = existing owner artifact and Packages MB + artifact MB + package MB
```

The publisher passes only when every input is stated, cleanup bounds retained versions, and the
projection is no greater than 500 MB. An omitted lifecycle, unbounded version count, missing input,
or projection above 500 MB violates this standard.

### Actions caches

Treat Actions cache storage as a separate repository allowance. Keep the configured cache limit at
or below 10 GB and cache retention at or below 7 days. Estimate cache churn as:

```text
cache GB = average entry GB * key variants per ref * active refs within retention
```

When the estimate could exceed the configured limit, non-default and pull-request refs may restore
matching caches but must not save new entries. A cache passes when the live settings meet both caps
and either writes are default-branch-only or the declared churn estimate stays within the cap. A
higher live limit, longer retention, or forecasted over-cap ref writes violates this standard.

### Billing hard stop

The personal-account owner must maintain an Actions budget of `$0`; GitHub user-level budgets always
hard-stop automatically and do not offer a stop-usage toggle. Organization owners using this rule
must also enable **Stop usage when budget limit is reached**. Repository code cannot prove the
applicable account control, so treat it as `unenforced-by-repo` and verify it through Billing
settings without recording private details in this public repository.

## Examples

Use one-day retention for a cross-job handoff:

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: test-output
    path: reports/test-output.json
    retention-days: 1
```

When ref churn could exceed the cache allowance, use `actions/cache/restore` on all refs and guard
`actions/cache/save` with `github.ref == 'refs/heads/main'`.

## Validation

Review every changed workflow for artifact uploads, package publishers, cache actions, and built-in
tool caches. Record the applicable calculations in review evidence. Verify repository artifact
usage, cache usage, artifact/log retention, cache limit, and cache retention from live GitHub
settings; verify the owner `$0` hard stop separately in Billing settings.

The 2026-09-05 baseline for Beaver Nest is:

- public repository;
- no active Actions artifacts, with 13 expired legacy records totalling about 6.4 MB;
- no package publisher in repository workflows; live package inventory remains unverified because
  the available token does not expose it;
- about 388 MiB of main-only cache entries;
- 7-day repository artifact/log retention; and
- no pull-request trigger in the scheduled workflow.

Policy review and live evidence are the enforcement route. The repository adds no validator while
it has no artifact or package publisher and its main-only cache remains far below the cap. Add a
deterministic validator when a future workflow introduces a machine-checkable storage obligation.
