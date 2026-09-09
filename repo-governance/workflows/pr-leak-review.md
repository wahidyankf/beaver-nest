# PR Leak Review

## Goal and When to Use It

Produce one narrow, posted review for the exact head that will merge. It is a
[merge precondition](../conventions/pull-request-merge.md): no posted leak review, no merge. Run it
on every pull request before merge, and again whenever the head moves.

Adapted from the sibling repository that originated the rule. What changed here: no separate
reviewer agent, so the review is performed by whoever handles the merge; the categories are the
ones [data safety](../conventions/public-repository-data-safety.md) already names for this
repository; and the evidence marker keeps the sibling name so one reader can authenticate a record
from any of these repositories.

## Prerequisites

An open pull request, and a head SHA pinned before anything is read.

## What It Inspects

Exactly three categories, and nothing else:

1. Real secrets, credentials, or other values that grant access.
2. Properties that belong in environment or secret storage rather than a tracked file.
3. Real machine-specific absolute paths, and real host evidence captured from a workstation.

This is not a security review and not a semantic one. A public identifier, a documented public
value, an obvious placeholder, a repository-relative path, and a deliberately synthetic fixture are
not leaks. A name containing `key`, `token`, `secret`, or `prod` is not evidence by itself; treat a
candidate as a finding only where its shape and its context establish that the value is real.

## Steps

1. Pin the head SHA. Everything below concerns that SHA and no other.
2. Read the whole diff at it — not a summary, and not memory of what was written.
3. Post one review carrying the record below, whatever the result: a pass nobody wrote down is
   indistinguishable from a review nobody ran.
4. Read the review back and confirm its `commit_id` equals the pinned SHA.
5. Query the live head again.

```html
<!-- ose-pr-leak-review:v1
{"repository":"owner/repo","pull_request":0,"base_ref":"main",
 "base_sha":"<base SHA>","head_sha":"<reviewed SHA>","result":"pass|findings",
 "counts":{"secret_or_private_value":0,"protected_environment_property":0,
 "machine_specific_absolute_path":0}}
-->
```

## Verification

`pass` when every count is zero, `findings` when any is not, `stale` when the head moved before or
after posting, `failed` when no verdict could be obtained. Only `pass`, on the exact head being
merged, satisfies the precondition. A moved head needs one new review; clean reviews never
accumulate.

## Recovery

Name the category, the file, and the remediation. Never repeat the value, and never paste it into a
review body, a commit message, or a pull-request body — those are published too. Treat anything
found as already disclosed: rotate first, then remove.

The review body is itself a published artifact. A local absolute path pasted into it is the same
finding this review exists to catch.
