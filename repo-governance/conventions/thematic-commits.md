# Thematic Commits

Every commit must represent one coherent purpose that can be understood, reviewed, and reverted independently.

## Requirements

- Include all code, tests, documentation, and configuration needed to complete the commit's purpose.
- Exclude changes serving a separate purpose, even when they were made during the same task or exist in the same working tree.
- Separate independently useful or revertible changes into distinct commits and order dependent commits logically.
- Inspect the working tree and staged diff before committing. Stage one theme at a time when multiple themes are present.
- Describe the single purpose accurately in the commit message.
- When asked to commit all changes, create as many thematic commits as necessary rather than combining unrelated work.

A theme is defined by intent, not file type or directory. For example, a feature and its tests and documentation form one theme; an unrelated typo fix forms another.

This convention makes history easier to review, revert, bisect, and reuse without separating changes that are necessary for one complete outcome.
