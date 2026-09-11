# Public Safety

This repository is published, so everything it emits — file contents, file names, commit messages, branch names, tags,
release notes — is outbound material. This directory is the gate that screens all of it, and it is the first gate to run
on every surface that has one.

Two scripts and the set they read, deliberately separate:

| File                    | Owns                                                                |
| ----------------------- | ------------------------------------------------------------------- |
| `check.sh`              | what is outbound at a given surface                                 |
| `outbound-preflight.sh` | whether any of it is prohibited                                     |
| `shape-terms.txt`       | the generic private-metadata shapes screened for, alongside secrets |

The split is what lets the leaf be tested with synthetic inputs and no repository at all, and it is why the leaf never
runs `git`.

## The Gate

```bash
OSE_GATE_SURFACE=<commit-msg|pre-commit|pre-push|ci> scripts/public-safety/check.sh [hook arguments]
```

The surface arrives in the environment and nowhere else. A missing or unknown value is a protocol failure, not a
default. A gate that infers its own surface will eventually infer a weaker one, and that is exactly the case where
inferring is expensive.

| Surface      | Outbound at that moment                                           |
| ------------ | ----------------------------------------------------------------- |
| `commit-msg` | the message being written, and the current ref name               |
| `pre-commit` | the tracked tree and its names, then the staged additions         |
| `pre-push`   | the refs being pushed, the outgoing commit messages, and the tree |
| `ci`         | the ref, the head commit message, and the checked-out tree        |

`pre-commit` screens the whole tracked tree, not only the change. A leak that is already committed does not become safe
because this particular commit did not introduce it.

## The Leaf

```bash
scripts/public-safety/outbound-preflight.sh --surface <surface> \
  [--text <string>]... [--file <path>]... [--terms <path>]
```

| Exit | Meaning    | What it means for publication  |
| ---: | ---------- | ------------------------------ |
|    0 | clean      | may proceed                    |
|    1 | blocked    | must not proceed; a finding    |
|    2 | scan error | must not proceed; not screened |

`1` and `2` are both refusals. They differ only in whether we know what is wrong. A scan that could not run is not a
scan that passed, and there is no allowlist, suppression, or bypass for either.

Leaf surfaces are `baseline`, `diff`, `commit`, `ref`, `pull-request`, `release`, and `logs`. A surface outside that set
exits `2`, and so does a surface given no input.

## How It Screens

Two layers, in this order:

1. **Shape screening.** Each input is matched against `shape-terms.txt`. The input's own path is screened too: a path
   that is itself prohibited is reported as `<blocked-path>` rather than printed.
2. **Credential scanning.** TruffleHog `v3.97.1`, pinned by SHA-256, downloaded once into a cache outside the
   repository, verified before extraction, and run offline with
   `--no-verification --no-update --fail --fail-on-scan-errors`.

Before either layer touches real material, a **canary** runs: a real RSA key generated at run time, scanned, and
required to produce a detection whose output does not contain the key. The canary proves detection _and_ non-disclosure.
A random token-shaped string would prove neither — the token detectors validate a checksum, so an invented `<token>` is
simply not detected.

## The Shape Set

`shape-terms.txt` holds shapes, never values: an absolute home directory, a private address range, an internal hostname
suffix. It is published, so a denylist of real names would publish exactly what it exists to protect.

A workspace that must also screen for named private identifiers keeps that list outside every public checkout and passes
it with `--terms`. That second layer is the owner's, not this repository's.

The set is validated before it is trusted. Absent, unreadable, empty, comments-only, malformed, or carrying a
credential-shaped value all exit `2`. An empty set is rejected precisely because it cannot be distinguished from "this
repository has nothing to screen for" — the one answer that would be wrong.

## Output

The entire diagnostic vocabulary is four fields:

```text
[public-safety] <status> <detector> <path>:<line>
```

`status` is `finding`, `scan-error`, or `blocked`; `detector` is a class name from the shape set or a TruffleHog
detector name; `path` is repository-relative and screened; `line` is an integer.

Matched text, term values, decoder output, verification errors, commit author data, and raw scanner JSON never appear —
not on stdout, not on stderr, not in a temporary file, not in evidence. Raw scanner output flows through an in-memory
pipe into a strict field extractor and nothing else survives; a record whose shape is not recognized is a scan error,
which blocks.

## What Is Prohibited

Secrets and credentials; personal data not intentionally public; maintainer absolute home paths; internal hostnames,
addresses, and topology; private repository identifiers; and raw detector output that could reproduce any of them.

Replace safe examples with semantic placeholders — `<api-token>`, `<private-host>`, `<repository-path>`. If replacement
destroys the artifact's meaning, the artifact does not belong in a public repository.

## Tests

```bash
bash scripts/public-safety/tests/run.sh            # all cases
bash scripts/public-safety/tests/run.sh 080        # one case by name fragment
```

| Case                        | Asserts                                                     |
| --------------------------- | ----------------------------------------------------------- |
| `010-missing-term-set`      | an absent term set blocks                                   |
| `020-empty-term-set`        | empty and comments-only term sets block                     |
| `030-malformed-term-set`    | short lines, unknown class or kind, bad regex, credentials  |
| `040-matching-content`      | literal, regex, and name matches all block                  |
| `050-clean-content`         | clean input passes, including against the tracked shape set |
| `060-non-disclosing-output` | a blocked run reproduces neither credential nor term        |
| `070-surface-coverage`      | all seven leaf surfaces accept, block, and reject unknowns  |
| `080-tracked-shape-set`     | every tracked shape matches, and ordinary text still passes |
| `090-surface-dispatch`      | a missing, empty, or unknown gate surface is a scan error   |

Every probe value is assembled at run time from fragments, so no string this repository's own gate would flag exists in
any test file — a test that hardcoded one would block the commit that added it. `assert_absent` reports only a length on
failure: naming the value would make a failing test the disclosure the test prevents.
