# HIPPO Consumer Behaviours

The `.feature` files in this directory form the canonical executable behaviour corpus for the root
HIPPO consumer wrapper. The production-backed
[shell adapter](../../../../.github/scripts/test-hippo-bootstrap.sh) must bind every scenario exactly
once, reject missing or unknown scenarios, and invoke the real wrapper for each install-lock case.
The [scheduled repository contract](../../../../.github/workflows/scheduled-quality-gates.yml) runs
that adapter on both supported operating systems.

## Directory Map

- [HIPPO bootstrap](hippo-bootstrap.feature) specifies safe install-lock ownership and
  reclamation, plus the retention rules that keep one shared cache root safe for every
  repository using it.
