# 007. Codex Generated Images Shown Inline In The Codex Chat

Date: 2026-11-15

Status: Accepted (2026-11-15). The owner chose option C (grill decision). Open points 1-4 below remain as stated
follow-ups.

Extends [002](002-codex-chat-markdown-and-images.md), Decision 2 (a second image route with the same safety rules) and
[003](003-inline-chat-images-and-shared-markdown.md), Decision 4 (one more sentence in the Codex instruction). Nothing
in 002, 003, 004, 005 or 006 changes otherwise: the repository image route, the `https`/`data:` classifier rows, the
shared renderer shape, and the Family Chat exclusion principle all stay as written.

## Context

A Codex turn that generates an image leaves Bnest with nothing to show. Checked in
`local-tmp/chat-session-handoff/image-investigation/REPORT.md` against the real CLI (bundled 0.149.1 and installed
0.164.0, same SDK options as production): `codex exec --experimental-json` emits no image item at all. The PNG is
written to disk at `~/.codex/generated_images/<thread_id>/exec-<uuid>.png` (observed 1.4 to 2.9 MB, 1536x1024) and
recorded only in Codex's own session rollout file, which Bnest never reads. `chat_runner.mjs` forwards only
`thread.started`, `agent_message`, `reasoning`, `web_search`, `turn.completed`, `turn.failed` and `error`; every other
item type falls through the `if/else if` chain with no `else` and is silently dropped. The final assistant text carries
no reference either: the tool result the model sees says "The generated image is already displayed to the user. There is
no need to render it in the final response as a Markdown image or file link." So the model writes plain text, and even a
written path would be refused by `ChatMarkdown` (absolute paths, `~`, dot segments and anything outside the working
directory all classify as `:other`).

The owner chose option C from that report: the model places the reference inline (primary path), and the runner appends
any image the model did not reference at the end of the reply (fallback). This record designs that option. No code is
changed by this record.

Facts checked in the code on 2026-11-15 (main at `c45234a`):

- `ChatMarkdown.to_html/3` takes an options keyword (`:parse_time_ms`, `:hard_breaks`); the image gate is
  `classify_image/1` with five fixed rows and no caller option. Both rooms share it: `ChatLive` renders assistant
  replies through `ChatComponents.markdown_body/1`, and Family Chat bodies go through
  `ChatComponents.markdown_body_html/2` into the GraphQL `bodyHtml` field. Own visitor messages in `/chat` also render
  through `markdown_body/1` (ADR 005).
- `GET /chat/images/*path` sits in the `[:browser, :authenticated_browser]` scope (`router.ex:108`);
  `ChatImageController` answers every refusal with an empty `404` carrying `cache-control: private, max-age=60` and
  `content-security-policy: default-src 'none'; sandbox`. The facade `CodexChat.repository_image/1` runs syntax, port
  read, then signature check, and the adapter `lstat`s every component below the configured working directory, refusing
  any symlink.
- `config :bnest_app, :codex` today holds only `working_directory:` (`config.exs`, `runtime.exs` override from
  `BNEST_CODEX_WORKING_DIRECTORY`). There is no `CODEX_HOME` value.

## Decision 1. A generated-image reference only the Codex room renders

New Markdown reference form, written by the model (Decision 3) or appended by the fallback (Decision 4):

```text
![alt](codex-image:<thread>/<file>)
```

where `<thread>` is the Codex thread id and `<file>` is the saved file name, e.g.
`![Generated image](codex-image:01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071/exec-2b5e6589-1111-2222-3333-444455556666.png)`.

Classifier rule (first match wins, ordered before the repository row is unchanged; the new row sits directly after it):

- **1b**
  - Destination: Scheme `codex-image`, remainder `<thread>/<file>` matching the strict name rule, **and** the render
    option `codex_images: true`
  - Result: `{:codex_generated, thread, file}`, rendered as `<img src="/chat/generated-images/<thread>/<file>">`
- **—**
  - Destination: Same shape with `codex_images:` absent or false (every other caller)
  - Result: `:other`: `[image not shown: alt]`, as today

The render option is named `codex_images` (default `false`), threaded through `ChatMarkdown.to_html/3`,
`ChatComponents.markdown_body/1` (new attr, default `false`) and `markdown_body_html/2` (new keyword, default `false`).
Only the assistant-reply call site in `ChatLive` passes `codex_images: true`. Family Chat (`family_chat_types.ex` via
`markdown_body_html/2`), the visitor own-message rendering (ADR 005), streaming placeholders and any future caller keep
the default, so a guessed or pasted `codex-image:` destination there stays text. This is the same exclusion the report
requires: names are unguessable uuids, but the rule must not exist outside the Codex room.

While streaming (`auto_close`), an unfinished `![alt](codex-image:exa` is plain text, exactly like an unfinished `https`
address: an image renders only once its closing `)` has arrived.

## Decision 2. Route, storage root, and refusal rules

`GET /chat/generated-images/*path`, handled by a new `GeneratedImageController`, in the existing
`[:browser, :authenticated_browser]` scope, next to `/chat/images/*path`. Any signed-in role may use it, the same
audience as `/chat`: children can already ask Codex about anything the sandbox reads, so the route narrows nothing new
beyond raster bytes the model itself produced.

- **Root.** `config :bnest_app, :codex, :codex_home`, default `~/.codex`; override from a new environment variable
  `BNEST_CODEX_HOME` (name to be added to the config docs). The route resolves only under
  `<codex_home>/generated_images`, read from config inside the adapter, never from the request. The router decodes each
  `*path` segment once; the controller joins and never decodes again (same shape as `ChatImageController`).
- **Strict names.** After joining, the path must be exactly two segments, `<thread>/<file>`. Thread:
  `^[0-9A-Fa-f-]{1,64}$` containing at least one hyphen (Codex thread ids are uuid-shaped; the pattern accepts their
  shape without pinning a version). File: `^exec-[0-9A-Za-z-]{1,64}\.(png|jpg|jpeg|gif|webp)$`, extension compared
  without case. Anything else (empty, absolute, `\`, NUL, `%` left after the one decoding, `:`, `.`/`..`/empty segments,
  any other segment count, any other extension, any SVG) is refused. The thread shape keeps `..` unrepresentable even
  before the segment rules run.
- **Containment.** Same rule as the repository adapter: `File.lstat/1` per component below the root, directory for the
  parent, regular file for the last; any symlink below the root refused.
- **Size.** 5 MiB cap shared with `RepositoryImage.max_bytes/0` (observed generations are 1.4 to 2.9 MB); bounded read
  of `max + 1`, refuse when more arrives.
- **Content.** Signature check reuses `RepositoryImage.signature/1` (PNG, JPEG, GIF87a/89a, `RIFF....WEBP`); the served
  `Content-Type` comes from the sniffed bytes, never the extension. HTML, text or SVG renamed to `.png` is refused. No
  SVG in any form.
- **Response.** 200 with the in-memory bytes: fixed image type, `cache-control: private, max-age=60`,
  `content-security-policy: default-src 'none'; sandbox`, plus the pipeline's `x-content-type-options: nosniff`. No
  `Content-Disposition` filename, nothing from the request in any header. Every refusal (bad name, denied, missing,
  symlink, not a file, too large, wrong signature, read error) is the same empty `404` with the same headers, so the
  route is not an oracle for which generations exist.

A parallel facade `CodexChat.generated_image(thread, file, options \\ [])` mirrors `repository_image/1`: strict-name
check (pure, unit-tested), then the port read, then the signature check. A new port `Ports.GeneratedImages` with an
in-memory test double keeps unit tests off the disk, exactly as `RepositoryImages` does today.

## Decision 3. The Codex instruction (primary path)

`priv/codex/chat_instructions.mjs` gains one paragraph (constant text, no visitor value interpolated; delivered by the
same `developer_instructions` wiring whose contract test already pins verbatim delivery):

```text
When you generate an image, show it where it belongs in the answer with ![alt](codex-image:<dir>/<file>) using the last
two segments of the saved path (the thread directory and the file name), for example
![Generated elephant](codex-image:01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071/exec-2b5e6589-1111-2222-3333-444455556666.png).
Write one reference per image, in place, in the middle of the text. Never write absolute paths, ~/.codex paths, or
file:// addresses.
```

This paragraph deliberately contradicts the image skill's "no need to render it" sentence; a `developer` instruction is
the documented override point (ADR 002, Decision 3). Whether the model complies on every turn and model is **not**
established: the captures in the report used the current instruction text, which says nothing about generated images. A
follow-up experiment with the proposed sentence must run before or with the build, and its result is recorded here. A
hallucinated name fails the strict-name check or misses on disk and renders as `[image not shown: alt]` (safe degrade,
never a broken fetch).

## Decision 4. Runner and transcript fallback

At turn start the runner lists `<codex_home>/generated_images/<thread_id>/`; at `turn.completed` it lists again and
emits one new `image_generated` event (`{item_id, file}`) per new file, in lexical order. `CodexPortSession` forwards
it; `Transcript` appends `![Generated image](codex-image:<thread>/<file>)` to the reply content for each file whose name
does not already occur in the final text. Inline position is kept whenever the model complies (the normal case if the
instruction holds); otherwise the image lands at the end of the reply instead of being lost. Several images each get
their own reference, placed or appended in order.

No polling, no rollout-file parsing: the report rejects depending on Codex's undocumented internal rollout format, and
the diff needs only two listings. The fixture runner must emit the same event so contract tests can drive the fallback
without a model.

The reference lives in the message `content` string, so snapshot, reload, restore and reconnect show the same order with
no snapshot version change and no binary in the record.

## Decision 5. What is out of scope

- **Retention.** Codex never deletes `generated_images`. Bnest does not delete from Codex's home without an owner
  decision. Links in old transcripts work only while the files exist; after cleanup they show `[image not shown: alt]`.
  Document this; a retention task is a later owner decision, not this change.
- **Backfill.** Existing transcripts keep plain text; no rollout-file backfill (rejected in the report: undocumented
  format, and old replies have no position data).
- **`data:` embedding** stays rejected (32,768 base64 cap vs megabyte images; 100 KB message cap). **Copying the image
  into the repository** (e.g. `workspace-write` + model copy) stays rejected: it weakens the read-only boundary,
  pollutes git, and the path deny set blocks most outputs.
- **Family Chat** never renders `codex-image:` (Decision 1). The renderer stays shared; only the room-specific option
  differs, per the 003 principle of one renderer.
- **Size cap change.** If a generation exceeds 5 MiB it shows `[image not shown: alt]`. Raising the cap for this route
  is a separate decision with its own memory-per-request cost.

## Threat notes (modeling-threats)

**Assets:** files beside the checkout (`~/.codex`, SSH keys, backups); the visitor's session; availability of the 24/7
service.

**Trust boundaries:** model output (untrusted, may be prompt-influenced) to the renderer; browser request to the new
route; new route to the Codex home directory; rendered HTML to the browser.

**Entry points added:** the `codex-image:` classifier row and render option; `GET /chat/generated-images/*path`; the
instruction paragraph; the runner `image_generated` event.

- **Model writes `~/.codex`, absolute or `file://` path**
  - Choice that closes it: Only the strict two-segment `codex-image:` form renders; everything else stays `:other`
  - Test that fails without it: Unit corpus: absolute, `~`, dot-segment and `file:` destinations give
    `[image not shown]`
- **Path traversal (`..`, `%2e%2e`, backslash, NUL, double encoding)**
  - Choice that closes it: Strict name regex on the joined path; router decodes once, domain never decodes; `%` left
    after decoding refused
  - Test that fails without it: Unit table of traversal strings; integration with encoded variants
- **Symlink escape out of `generated_images`**
  - Choice that closes it: `lstat` per component, any symlink refused
  - Test that fails without it: Integration: symlinked thread dir and symlinked file return 404
- **TOCTOU (swap after the check)**
  - Choice that closes it: Bytes read once and served from memory; signature on the bytes served
  - Test that fails without it: Accepted residual: a writer inside Codex's home can only swap in another
    raster-signature file
- **Content sniffing / SVG or HTML as image**
  - Choice that closes it: Extension allowlist plus signature sniff; fixed `Content-Type`; `nosniff`; response CSP
    `sandbox`
  - Test that fails without it: Integration: SVG, HTML and text named `.png` return 404; headers asserted
- **Header injection / XSS through headers**
  - Choice that closes it: No request value in any header; no `Content-Disposition` filename
  - Test that fails without it: Integration: header set is exactly the expected list
- **Existence oracle (which generations exist)**
  - Choice that closes it: One identical empty 404 for every refusal
  - Test that fails without it: Integration: missing, denied and symlinked paths give equal status, headers and body
- **Denial of service through size**
  - Choice that closes it: 5 MiB cap with bounded read; `loading="lazy"` limits fan-out
  - Test that fails without it: Integration: 5 MiB + 1 byte file returns 404
- **Cross-user read**
  - Choice that closes it: Same audience as `/chat` and `/chat/images` (any signed-in role); generations come from this
    machine's shared Codex home, not per-user data
  - Test that fails without it: Integration: signed-out request redirects to `/login`; no image bytes in the body
- **Family member embeds owner's files by guessing names**
  - Choice that closes it: Render option defaults false; Family Chat, own-messages and all other callers keep the
    default
  - Test that fails without it: Unit: `codex-image:` reference through the Family Chat path yields `[image not shown]`;
    byte-equality test of the two `markdown_body_html/2` paths with the option on and off
- **Tracking / exfiltration through generated-image URL**
  - Choice that closes it: No third party: same-origin route, `referrerpolicy="no-referrer"` kept
  - Test that fails without it: Unit: emitted `<img src>` starts with `/chat/generated-images/` only
- **Instruction injection through the new paragraph**
  - Choice that closes it: Constant text in the repository; no visitor value interpolated
  - Test that fails without it: Contract test on the instruction text (Decision 3)
- **Stale open page during rollout sees new reference**
  - Choice that closes it: Old revision has no `codex_images` row: renders `[image not shown: alt]`, no fetch, no error
  - Test that fails without it: e2e/reconnect note in the rollout proof (no new code path on the old revision)

## Tests and specs, in order

Spec first (Gherkin, then bindings, Nx red, code, smoke), per the specification maintenance rule. The scenarios below
are the plan; none is written by this record.

`specs/apps/bnest/app-fe/behaviours/chat.feature`, Rule "Codex reply images" (or a new Rule "Codex generated images" if
the room prefers; the feature file is the source of truth):

- `A Codex reply shows a generated image where the model places it`
- `A generated image the model does not reference is appended at the end`
- `Several generated images keep their order`
- `A wrong generated-image name stays as text` (hallucinated name, traversal, absolute path)
- `A signed-out visitor cannot fetch a generated image`
- `A generated image behind a symbolic link is refused`
- `A generated image over the size limit is refused`
- `A file that is not a raster image is refused`
- `Hidden thread directories are refused`
- `A generated image does not render in Family Chat` (binds in `family_chat.feature`: a message carrying a
  `codex-image:` reference stays text; alternative proof at unit level)

Unit (inside the 99% gate): strict-name table (valid, traversal, double encoding, bad extension, three segments, SVG);
facade size check against a double that ignores limits (mirrors the ADR 002 decoy pattern); option default `false` for
`to_html/3`, `markdown_body/1` and `markdown_body_html/2`; byte-equality of the two markup paths with the option on and
off; streaming half-written reference stays text; XSS corpus extended with `codex-image:` variants.

Integration (`bnest-app:test:integration`): real adapter over an isolated run root — valid PNG round-trips with sniffed
content type and exact security headers; missing/denied/symlinked/ oversized/wrong-signature give identical empty 404s;
every Family Chat role still gets 200 for `/chat/images` (unchanged) and for a planted generated image (same scope);
signed-out redirects to `/login`. Contract test: `developerInstructions` contains the new paragraph verbatim through the
installed CLI (`codex debug prompt-input`), and the production runner passes it via `config.developer_instructions`
(extends `chat_instructions_test.exs`). Fixture runner plus `codex_fixture_replies.json`: a generated-image case driving
the `image_generated` fallback.

Browser e2e: one generated image decodes inside the bubble at 390 px and 1280 px (`scrollWidth <= clientWidth`,
`naturalWidth > 0`); reconnect ADR-pattern proof that an old revision shows `[image not shown: alt]`.

## Consequences

### Positive

- Image-generating turns show their pictures inline, at the model's chosen position, with a no-model-cooperation
  fallback that loses nothing.
- All safety rules sit in the same two shapes as 002: a pure classifier row plus a route whose adapter owns containment,
  size and signature. One new config value, no migration, snapshot version stays 4.
- Old revisions degrade safely (withheld text, no fetch), and old transcripts are untouched.

### Negative

- One more thing the model must be told, against its skill text; compliance is unproven until the Decision 3 experiment
  runs.
- The runner now touches the file system twice per turn (two directory listings of one thread dir); negligible, but it
  is new I/O in the turn path.
- Generated images are fully read into memory per request (same as 002's 5 MiB rule).
- Links in old transcripts rot when Codex's home is cleaned outside Bnest; the withheld text is the honest remainder.

### Rollout and rollback

A normal release carrying the route, the classifier option, the instruction text and the runner change together (the
instruction only takes effect on the next `codex exec` per turn, so running processes pick it up on their following
turn; no restart choreography beyond the deploy itself). The deployer follows live-service continuity: start the
candidate on a loopback port, switch Caddy with a graceful reload, show the routed `X-Bnest-Revision` equals the new
revision, keep the previous backend through the bounded WebSocket drain, and let open `/chat` LiveViews reconnect on
their own. Then, through the routed origin: fetch one real generated image (200, sniffed content type, exact headers),
refuse one bad name (empty 404), load one reply with an inline generated image in `/chat`, and confirm an old-revision
page shows the withheld text. Do not assume a browser refresh. Rollback is the previous revision with no data change;
the new references stay stored as text and render once the new revision returns.

## Open points for the owner

1. The `BNEST_CODEX_HOME` variable name (Decision 2) is proposed; confirm or rename before the build writes
   `runtime.exs` and the config docs.
2. Model compliance with the Decision 3 paragraph against the skill's "no need to render it" sentence: run the follow-up
   experiment (same capture script, proposed instruction) and record the result here before calling the primary path
   proven.
3. Whether a generation over 5 MiB should raise the cap for this route only (Decision 5 says no for now).
4. Retention for `generated_images` (Bnest never deletes without an owner decision).
