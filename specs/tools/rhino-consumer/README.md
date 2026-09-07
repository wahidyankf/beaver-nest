# RHINO Consumer Specification

This specification owns the observable behaviour of BeaverNest's root `./rhino` consumer bootstrap.
The independent upstream RHINO repository continues to own the executable, its command surface, its
configuration schema, and its release artifacts; this corpus does not duplicate those concerns.

The bootstrap is a documented fork of the root `./hippo` consumer, and the corpus is deliberately
close to [the HIPPO consumer specification](../hippo-consumer/README.md): the two wrappers solve the
same problem — install a pinned, checksummed release exactly once on a machine several repositories
share — and a divergence between them should be a decision someone made rather than a detail that
drifted. Where a scenario differs, the difference is the point.

## Directory Map

- [Behaviours](behaviours/README.md) specify safe release installation and local bootstrap behaviour.
