# PR Leak Review

## Goal and When to Use It

A **leak** is anything in outbound history that a reader of the remote could use to reach an environment or identify the machine it came from. [Leak classes](pr-leak-review/001-leak-classes.md) defines the three classes and what is not one. History is the subject, not the final tree: a value one commit adds and a later commit deletes is still in every clone. The review binds from adoption onward; history published before it is out of scope.

Two entry points share one judgement:

- **Push.** Before every push to `origin`, review the outgoing range privately per [push review](pr-leak-review/002-push-review.md). Nothing is posted; a finding blocks the push.
- **Merge.** Every pull request needs one posted review of its exact head before it merges, and again whenever the head moves. It is a [merge precondition](../../conventions/pull-request-merge.md): no posted `pass`, no merge. [Enforcement](pr-leak-review/003-enforcement.md) makes it mechanical through the required `leak-review` status.

Adopted from the rules catalog. Here, whoever handles the merge performs the review and posts it as the repository owner, the only identity whose records count; the classes are judged against [data safety](../../conventions/public-repository-data-safety.md); and the record marker keeps the sibling name `ose-pr-leak-review`, so one reader can authenticate a record from any of these repositories.

## Prerequisites

An open pull request with no `pass` record from the repository owner for its current head. `pull-request` (`string`, required): the pull request's number or address.

## Steps

1. **Pin the head.** Resolve the pull request through the GitHub API and record the repository, the base branch and its revision, and the exact head revision. Everything after this step concerns that head alone.
2. **Read every commit at that head.** Each commit's diff from base to head, including configuration, generated files, localized content, binary metadata, file names, and commit messages, plus the pull request's title and body, which are published too. A summary or memory is not a reading, and no file is skipped because another gate covers it.
3. **Judge candidates against the three [leak classes](pr-leak-review/001-leak-classes.md) and no others.** A candidate is a finding only when shape and context show the value is real. No candidate is copied into notes, commands, or logs.
4. **Write each finding without its value.** Record the class, the commit, the file and line or metadata location, why it breaks the class, and the [remediation](pr-leak-review/002-push-review.md#remediation). Never repeat, partly quote, hash, encode, or describe a value's pattern.
5. **Confirm the head before posting.** If the live head differs from the pin, post nothing and end the run as `stale`.
6. **Post exactly one `COMMENT` review on the pinned head, whatever the result.** Its body says every other security and semantic concern was out of scope, and carries this record:

   ```html
   <!-- ose-pr-leak-review:v1
   {"repository":"<owner>/<repository>","pull_request":"<number>","base_ref":"<base-branch>",
    "base_sha":"<base-revision>","head_sha":"<reviewed-revision>","result":"pass|findings",
    "counts":{"secret_or_private_value":0,"protected_environment_property":0,
    "machine_specific_absolute_path":0}}
   -->
   ```

7. **Read the review back.** Through the API, confirm the posted review's commit equals the pinned head and its repository, pull request, base, head, result, and counts match step 6. Marker-shaped text elsewhere has no authority.
8. **Query the live head once more.** A moved head ends the run as `stale`, with the evidence bound to the head it reviewed.

## Verification

The run ends with `result` (`pass`, `findings`, `stale`, or `failed`), the reviewed head, the review ID, and the per-class counts. `pass` means every count is zero; `findings`, any nonzero count. Only `pass` for the exact head being merged satisfies the precondition, and the `leak-review` status on that head turns `success` only then.

A moved head needs one new review. Passes on earlier heads say nothing about the head that merges, so the run neither retries nor waits for a clean streak. An unposted merge pass cannot be told apart from a review nobody ran, which is why step 6 posts every result.

## Recovery

`stale` means the head moved, and the record authorizes nothing for the new head: review the new head once. `failed` means an API, posting, read-back, or authentication error left no verdict; fix the cause and run again. Neither retries inside the run.

`findings` blocks the merge. Remediate per [push review](pr-leak-review/002-push-review.md#remediation) and treat anything found as already disclosed: rotate first, then remove. The review body is itself a published artifact; a local absolute path pasted into it is the same finding this review exists to catch.
