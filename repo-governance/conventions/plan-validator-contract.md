# Plan Validator Contract

Plan structure is validated by more than one implementation. They are required to accept and reject exactly the same
inputs, with the same rule identifiers, the same messages, and the same exit classes.

That requirement only means something if the contract exists before either implementation does. Written afterwards, a
contract describes whichever one was built first, and the second is then judged against an accident.

## Modules

1. [Inputs and Exit Classes](plan-validator-contract/001-inputs-and-exits.md)
2. [Rule Identifiers and Messages](plan-validator-contract/002-rule-identifiers.md)
3. [The Shared Fixture Corpus](plan-validator-contract/003-fixture-corpus.md)
4. [Exclusions](plan-validator-contract/004-exclusions.md)

## What Freezing Means

A frozen contract may be extended. A new rule gets a new identifier and new fixtures, and the existing ones keep meaning
what they meant.

It may not be quietly redefined. A rule whose meaning changes gets a new identifier, because other tooling, other
implementations, and other repositories match on the old one and will keep matching after its meaning moved.
