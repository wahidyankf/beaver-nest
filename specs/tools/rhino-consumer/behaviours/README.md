# RHINO Consumer Behaviours

The `.feature` files in this directory form the canonical executable behaviour corpus for the root
RHINO consumer wrapper. The production-backed
[shell adapter](../../../../.github/scripts/test-rhino-bootstrap.sh) must bind every scenario exactly
once, reject missing or unknown scenarios, and invoke the real wrapper for each install-lock case.
The pre-push hook runs it locally for the paths that touch the consumer boundary, which catches a
corpus that no longer matches its implementation before the push rather than after it.

## Directory Map

- [RHINO bootstrap](rhino-bootstrap.feature) specifies safe install-lock ownership and reclamation,
  the retention rules that keep one shared cache root safe for every repository using it, and the
  isolation that keeps this wrapper and the HIPPO wrapper out of each other's state.
