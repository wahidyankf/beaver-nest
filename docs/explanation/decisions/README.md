# Architecture Decision Records

Decision records for Beaver Nest. Files are named `NNN-<slug>.md`; numbers are never reused; only the status line of an
accepted record changes.

## Directory Map

- [001. Fresh real SQLite database for every database-touching test](001-fresh-database-per-test.md) (Accepted) spawns,
  migrates, seeds and deletes one real database per integration test and per E2E scenario, behind a test-only,
  header-guarded control surface that is compiled out of production.
- [002. Markdown Codex replies with safe repository images](002-codex-chat-markdown-and-images.md) (Accepted) renders
  assistant replies as sanitized GitHub-flavoured Markdown with MDEx, shows repository raster images through an
  authenticated route, and asks Codex for that format with `developer_instructions`. 003 replaces its `https` and
  `data:` image rules. Ships with 003 and 004 as one release.
- [003. Inline chat images and one Markdown renderer for both chat rooms](003-inline-chat-images-and-shared-markdown.md)
  (Accepted) shows `https` and small raster `data:` images inline, renders Family Chat messages with the same
  `ChatMarkdown` through a server-rendered `bodyHtml` GraphQL field and a shared component, keeps message links, scroll
  regions and diagram sources reachable by keyboard in Family Chat (one tab group per stop message), and supersedes the
  image rules of 002. Ships with 002 and 004 as one release.
- [004. Mermaid diagrams in both chat rooms and one shared chat stylesheet](004-mermaid-diagrams-in-both-chat-rooms.md)
  (Accepted) draws `mermaid` fences in `/chat` and Family Chat through the shared Markdown component: the server marks
  only acceptable, complete diagrams, a lazily loaded Mermaid engine (own esbuild profile, no CDN) renders in strict
  mode inside a hidden same-origin frame, and the result is shown as a sandboxed `data:` image with the source kept as
  text. The shared chat styles live in `chat_shared.css` (tokens and `.markdown-body` rules), with the diagram rules in
  `diagrams.css`. Of the Decision 6 style tasks, 1 and 2 are built; 3 (shared sizing tokens) and 4 (container-based
  width) are recorded as not built follow-ups, and 7 (reduced motion) is not needed. Extends 003. Ships with 002 and 003
  as one release.
