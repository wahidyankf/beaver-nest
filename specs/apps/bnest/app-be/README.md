# Bnest Backend Specifications

This directory is the canonical backend specification entry point. `bnest-app` aggregates this root with
[`app-fe`](../app-fe/README.md) for its unit and local-only integration adapters; `bnest-app-be-e2e` is this root's
one dedicated E2E owner. See the [aggregate map](../README.md) for the full ownership rule.

## Directory Map

- [Architecture](architecture.md) describes the current as-built backend system through C4 views and constraints.
- [Behaviours](behaviours/README.md) contain the recursively executed backend Gherkin corpus.
