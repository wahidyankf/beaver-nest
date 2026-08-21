# Repository Governance

This directory contains the repository's detailed rules and working agreements.

Root instruction files such as `AGENTS.md` should remain concise—no more than 500 words—and link to the relevant documents here.

The `badakmini-cli` application enforces this limit for root `AGENTS.md` and every Markdown file in this directory. Run it manually with:

```sh
npm exec -- nx run badakmini-cli:check
```

The repository's pre-commit hook runs the same check automatically.
