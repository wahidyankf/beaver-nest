# Fixture Corpora

Shared fixtures this repository verifies against rather than authors.

## Corpora

[plan-structure/](plan-structure/README.md) — the plan-structure corpus. More than one implementation validates plan structure, and the claim that they agree only means something if they read the same bytes. This copy was adopted from `ose-rules` and is owned here: nothing pins it upstream.

## Verifying

```bash
cd specs/fixtures/plan-structure
shasum -a 256 -c SHA256SUMS
```

`SHA256SUMS` is a local integrity check over this copy, never a comparison against the catalog. A mismatch means these bytes changed since the digests were written; regenerate it in the same change that edits the corpus.
