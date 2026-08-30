# Dependency Selection

Prefer the language or platform standard library and existing repository mechanisms over a new external dependency. External code increases supply-chain exposure, upgrade work, compatibility risk, and long-term ownership even when its initial integration is small.

## Requirements

Add an external runtime, development, build, or test dependency only when all of these conditions hold:

- a concrete requirement cannot be met reasonably with the standard library or an existing repository mechanism without disproportionate correctness, security, interoperability, or maintenance cost;
- the dependency is an established community practice for that problem rather than a novel or repository-specific convenience; and
- current primary-source evidence shows active maintenance, compatibility with the repository's supported stack, and a credible response path for defects and security issues.

Record the requirement, considered built-in or existing alternatives, selection evidence, and ongoing ownership impact in the applicable plan or change description. Pin or lock the selected version through the ecosystem's normal reproducible mechanism and include it in existing dependency, security, license, and quality checks.

Do not introduce a dependency solely to reduce a small amount of clear repository-owned code, speculate about future needs, or avoid learning a capable standard-library facility. If the conditions above cease to hold, assess replacement or removal when the dependency is next materially changed or creates concrete risk; this standard does not require unrelated proactive churn.

## Verification

Review every changed dependency manifest or lockfile against the recorded decision. Verification passes when the need and rejected built-in alternatives are explicit, community adoption and maintenance claims use current primary sources, compatibility and ownership are addressed, and the repository's affected quality gates pass.
