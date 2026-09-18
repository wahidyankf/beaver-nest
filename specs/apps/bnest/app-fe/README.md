# Bnest Frontend Specifications

This directory is the canonical frontend specification entry point. `bnest-app` aggregates this root with
[`app-be`](../app-be/README.md) for its unit and local-only integration adapters; `bnest-app-fe-e2e` is this root's
one dedicated E2E owner. See the [aggregate map](../README.md) for the full ownership rule.

## Directory Map

- [Architecture](architecture.md) describes the current as-built frontend system through C4 views and constraints.
- [Behaviours](behaviours/README.md) contain the recursively executed frontend Gherkin corpus.
