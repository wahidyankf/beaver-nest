# HIPPO Consumer Behaviours

The `.feature` files in this directory form the canonical executable behaviour corpus for the root
HIPPO consumer wrapper. The production-backed
[shell adapter](../../../../.github/scripts/test-hippo-bootstrap.sh) must bind every scenario exactly
once, reject missing or unknown scenarios, and invoke the real wrapper for each install-lock case.
The [consumer smoke workflow](../../../../.github/workflows/hippo-consumer-smoke.yml) runs that
adapter on both supported operating systems, on every push that touches the consumer boundary and
twice daily. The pre-push hook runs it locally for the same paths, which catches a corpus that no
longer matches its implementations before the push rather than after it.

## Directory Map

- [HIPPO bootstrap](hippo-bootstrap.feature) specifies safe install-lock ownership and
  reclamation, plus the retention rules that keep one shared cache root safe for every
  repository using it.
