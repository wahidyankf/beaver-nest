# Technical Shape and Ordered Companions

A plan carries exactly one technical shape:

| Shape       | Form                                          | Choose when                                                             |
| ----------- | --------------------------------------------- | ----------------------------------------------------------------------- |
| single file | `tech-docs.md`                                | the technical design fits in one document a reader will actually finish |
| directory   | `tech-docs/README.md` plus ordered companions | it does not                                                             |

Never both. A plan root containing `tech-docs.md` _and_ `tech-docs/` is a validation failure, not a transitional state,
because the two will diverge and nothing decides which is authoritative.

Growing out of the single-file shape is normal. Converting means deleting `tech-docs.md` in the same change that creates
`tech-docs/`, so the plan never holds both.

## Companion Naming

When the shape is a directory, `tech-docs/README.md` is the entrypoint and every other document is a companion named:

```text
NNN-descriptive-kebab-case.md
```

- `NNN` is exactly three digits, zero-padded: `001`, `002`, … `010`.
- Numbering starts at `001` and is contiguous. No gaps, no duplicates, no `000`.
- The remainder is lowercase, alphanumeric, hyphen-separated, and describes the content. `007-release-packaging.md`, not
  `007-part-7.md` and not `007-misc.md`.
- The numeric order **is** the reading order.

Three digits rather than two because a companion set that outgrows `99` would otherwise have to be renumbered wholesale,
and one that outgrows `9` under two digits sorts `10` before `2` in every tool that sorts lexically.

## The Entrypoint Declares the Order

`tech-docs/README.md` lists every companion as a link, in numeric order. That list is the contract: a companion on disk
but absent from the list, or listed but absent from disk, is a failure.

The list exists because the ordinal in a filename tells a reader the sequence but not the reason for it. The entrypoint
is where the sequence is explained.

## Renumbering Is Atomic

Inserting a companion between `003` and `004` renumbers everything from `004` upward, updates the entrypoint list, and
updates every inbound link — in one change. There is no `003a`, no `003.5`, and no reuse of a number freed by a
deletion.

This costs more than appending, and that cost is the point: it keeps the ordinals meaningful instead of turning them
into arbitrary identifiers that happen to be numeric.

## The Same Rule Elsewhere

Any ordered companion set a repository governs — not only plan technical documents — uses this naming. A reader who
learns it once should not have to learn a second variant.
