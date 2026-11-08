# Explanation

Explanation provides understanding-oriented discussions of context, relationships, reasons, and design.

See the [Diátaxis explanation guidance](https://diataxis.fr/explanation/) for the category's purpose.

## Directory Map

- [Decisions](decisions/README.md) holds architecture decision records that explain why a design was chosen, such as [001 Fresh real SQLite database for every database-touching test](decisions/001-fresh-database-per-test.md).
- [Hexagonal architecture](hexagonal-architecture.md) explains why Bnest's application code is split into bounded
  contexts, ports, and adapters, and how the build enforces the split.
