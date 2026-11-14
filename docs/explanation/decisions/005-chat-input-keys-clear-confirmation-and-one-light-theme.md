# 005. Chat input keys, Clear chat confirmation, one light theme, and own-message Markdown

Status: Accepted (2026-11-13). Decision 1 follows the visitor's pointer, never the screen width.
The owner asked for consistent chat rooms: the same keys in both message boxes, a safe
Clear chat, no dark mode, Markdown in the visitor's own Codex messages, and a phone layout that gives the conversation
most of the screen. Decision 8 of [004](004-mermaid-diagrams-in-both-chat-rooms.md) is partly superseded by this record:
its items 5 to 7 describe the theme buttons and the old header budget. Its other items stand.

## Context

- Shift+Enter sent the message in Codex chat, but Family Chat sent on Enter. A visitor had to learn two rules.
- Clear chat deleted the whole conversation with one click and no question.
- The app had a dark theme: a theme dock, a theme control in each room header, and a `data-theme` value stored on the
  server. The owner asked for dark mode to be removed from the whole app.
- Codex replies were Markdown, but the visitor's own messages were plain text. A visitor who pasted Markdown could not
  see how it would look.
- On a phone the Codex header took two rows, its controls scrolled sideways, and a visitor who wanted the conversation
  had little of the screen left.

## Decision 1. The visitor's pointer decides the keys (both rooms)

`apps/bnest-app/assets/js/chat_keys.js` owns the rule. `isTouchPointer` reads `matchMedia("(pointer: coarse)")` at each
key press, so a pointer change while the page is open takes effect at the next key press.

- A touch primary pointer: Enter starts a new line and Shift+Enter sends.
- A fine primary pointer (mouse, trackpad, or a laptop keyboard): Enter sends and Shift+Enter starts a new line.

`keyIntent` (in `chat_keys.js`) returns `ignore` for any key press that confirms an IME composition (`isComposing`), and
for keyCode 229, which Safari uses for the same Enter. `sendOnKey` runs the send once: a held send key (`repeat`) stops
the newline and sends nothing more. Both rooms call `sendOnKey`: the Family Chat mount (`mount_browser_composer.js`) and
the Codex message box (`installComposerKeys(window, window)` on `data-role="chat-composer"`). So the rooms cannot drift
apart. A send with a blank draft does not send. While Codex replies, the Codex box is read-only, not disabled. It keeps keyboard focus, takes no text, and never sends, so a reply in progress cannot be sent twice.

A pointer press on the Send button keeps keyboard focus in the message box, in both rooms (`keepFocusOnSendPress` in `chat_keys.js`
for Codex, and the Family Chat mount for Family). A browser would otherwise move focus to the button, and a phone's keyboard closes
when focus leaves the box. The Codex box has a LiveView hook (`ChatComposer`, `codex_composer_hook.js`): when the server clears the
box after a send, the hook puts back the text the visitor typed after the send, so that text is not lost.

The behaviour follows the input type, never the screen size. The rule never reads the user agent, the window width, a
viewport or a breakpoint. A narrow desktop window keeps the fine-pointer rule, and a wide touch tablet keeps the
touch-pointer rule. Two caveats are recorded on purpose:

- An iPad, or a phone with a Bluetooth keyboard attached, has a touch primary pointer, so it uses the touch rule.
- A touchscreen laptop whose primary pointer is fine counts as a desktop, so it uses the fine-pointer rule.

The Send button stays in both rooms on every device; it is the touch path. Each box has a hint that names the shortcut
for the visitor's pointer: "Enter to send, Shift+Enter for a new line" on a fine pointer, and "Shift+Enter to send" on a
touch pointer. On a touch pointer the hint takes no visible row. The hint is the box's accessible description
(`aria-describedby`), and only the visible wording is in that description. The hint changes when the pointer changes.

## Decision 2. Clear chat asks first

The Clear chat button opens a small confirmation (`role="alertdialog"`): "Delete all messages?", with "Yes, delete" and
"Cancel". Only "Yes, delete" sends the LiveView `clear` event. Cancel and Escape close it and keep the conversation.
Focus moves to Cancel when the dialog opens, and back to Clear chat when it closes. The dialog keeps 44 CSS pixel
targets and fits a 320 by 568 screen. The open and close state lives in the browser (`chat_controls.js`); the server
sees only the confirmed clear.

Role: the confirmation keeps `role="alertdialog"`. It is a question that the visitor must answer
right away, and focus moves to Cancel when it opens, so screen readers announce the question at once. It is not a modal:
it has no backdrop and no focus trap. The visitor can leave it at any time, so it closes in these cases:

- the options panel closes, by a tap outside it, by the Options button, or by Escape, so a reopened panel never shows a
  stale question;
- focus leaves its group (Clear chat and the confirmation buttons), so the question never stays open behind the page.
  Focus moves that the confirmation makes itself do not count as leaving;
- Escape is pressed while the confirmation is open, from anywhere on the page. Focus goes back to Clear chat only when it
  was inside the confirmation. Escape never moves focus when focus was outside the confirmation; it leaves focus where it is.

Hiding the confirmation never moves focus, except for the Cancel, Escape and "Yes, delete" paths above. A press that starts
inside the group is not treated as leaving, because Safari does not focus a button on click. The confirmation sits inside
the options panel on a phone, as in `chat_live.ex`.

## Decision 3. One light appearance; no theme control

The home page, the Codex chat and Family Chat have one light appearance, and no page shows a theme control.

- The theme dock, the room header theme controls, the `data-theme` attributes, the theme script and the daisyUI dark
  plugin are removed. The stylesheet defines one theme, `light`.
- The visitor's system dark preference has no effect.
- Kept as inert storage, on purpose: the server preference column (`theme` in the account record), the endpoint
  `PUT /preferences/theme`, and the one-time browser import of the old `phx:theme` key. Removing them is a separate,
  later change: it needs a data migration and a rollback check. Nothing reads the stored value any more.

## Decision 4. Visitor messages render Markdown, with a raw view

A visitor's Codex message renders with the same shared Markdown component as Codex replies (`hard_breaks`, so a line
break the visitor typed stays a break). Each own message has a "Show raw" control (44 CSS pixels) that switches to the
exact typed text, and "Show rendered" switches back. The raw text is in the page (hidden), so the switch is local and
the server is not asked again. The raw paragraph keeps white space (`pre-wrap`), and it is shown as text, never as HTML,
so a `<script>` or a `javascript:` link in a visitor's message cannot run or become a link in the raw view.

The visitor's bubble is dark, so the "Show raw" label takes the bubble's light text token and its focus ring takes the
light sun colour. The browser row "The Show raw control reads on the dark visitor bubble" measures both.

A ` ```mermaid ` fence in a visitor's own message is drawn, as it is in a reply. `mermaid_diagrams.js` draws every
`pre[data-bnest-diagram="mermaid"]` on the page, and the visitor's bubble is one of those. This is accepted as written.
No feature scenario covers it yet.

Family Chat's own messages already render through the shared component (003); this decision does not change them.

Images in a visitor's own message follow the same rule as images in a Codex reply (ADR 003, Decision 1, and the
classifier in `BnestAppWeb.ChatMarkdown`): a repository image or an `https` image is shown, and any other image shows as
`[image not shown: alt text]`. The "Show raw" and "Show rendered" labels stay in English, like the rest of the chat's
controls; a translated label is not part of this decision.

## Decision 5. The phone layout gives the conversation most of the screen

The budget is the share of the screen height that the conversation keeps when the composer is empty, and the space
that is not conversation. The rules apply on a phone (`max-width: 767px`) and on a short window
(`max-height: 33rem`).

| Screen (CSS px)        | Codex conversation share (at least) | Family history share (at least) |
| ---------------------- | ----------------------------------- | ------------------------------- |
| 320 by 568             | 60 percent                          | 58 percent                      |
| 360 by 640             | 64 percent                          | 62 percent                      |
| 390 by 844             | 72 percent                          | 75 percent                      |
| 844 by 390 (landscape) | 52 percent                          | 52 percent                      |

- Codex on a phone width (`max-width: 767px`): the header has two rows. The first holds the brand and the Options button
  (at least 44 px). The second holds the repository access state and the model badge. Nothing sits under the access
  state, so a tap on the brand never reaches the write toggle. The header is at most 110 CSS px tall. On a short
  landscape window the header is one row. The model selector, the reasoning effort selector and Clear chat move into an
  Options panel that hangs below the header, so it takes no room from the conversation. The model badge stays in the
  header, so the model is visible without the panel. A server patch keeps an open panel open (`keepOptionsState`, the
  LiveSocket `dom.onBeforeElUpdated` hook). The panel closes on Escape and on a tap outside it. It has no edge fade, and
  it does not cover the access state. The composer keeps its padding and a 44 px message box.
- Family Chat: the header is one 3.5 rem row; the composer keeps a 44 px message box.
- The space that is not conversation is at most 220 CSS px for Codex, in a typical view with three short messages. The
  newest message sits above the composer. For Family Chat the budget is 180 CSS px, and it is not met at 320 and 360
  wide; the accepted figure is stated under Accepted limits.

Measured in Chromium (touch pointer, empty draft, three short Codex messages):

| Screen (CSS px)        | Codex measured share | Family measured share |
| ---------------------- | -------------------- | --------------------- |
| 320 by 568             | 62.1 percent         | 62.4 percent          |
| 360 by 640             | 66.4 percent         | 66.6 percent          |
| 390 by 844             | 74.5 percent         | 81.3 percent          |
| 844 by 390 (landscape) | 54.8 percent         | 59.7 percent          |

The Codex targets are met at every size with the two-row header: 62.1 against 60, 66.4 against 64, 74.5 against 72, and
54.8 against 52. The Family targets are met everywhere. The Codex space that is not conversation is 215 CSS px at 320,
360 and 390 wide, under its 220 CSS px limit, and 176 CSS px at 844 by 390. The Family space is about 214 CSS px at 320
and 360 wide and 158 CSS px at 390 wide (the 180 CSS px budget is covered under Accepted limits). The Family targets are
unchanged, so this record does not claim the Family space at those widths.

Decision (2026-11-13): the header keeps two rows on phone widths. A one-row header at 320 CSS px cannot hold the brand,
the repository access state, the model badge and Options without hiding the brand name or shortening a label. Safety
comes first, and the access state must stay visible while the brand is never covered. So the Codex floors change from
65, 70, 75 and 50 percent to 60, 64, 72 and 52 percent, and the Codex space limit is 220 CSS px.

The header changes apply on phone widths only.

On a landscape phone with a fine pointer (the desktop Chromium project), the composer keeps its keyboard hint row. The conversation measured 193.8 CSS px of 390 with a half-rem row gap, just under the half-screen floor of 195 CSS px. The landscape rule therefore sets a quarter-rem row gap instead of a half-rem gap. The number 195 is not changed.

Accepted limits:

- In landscape on a phone, the Clear chat confirmation can cover part of the composer. It is transient: it shows only
  while the visitor answers the question, and it closes with the panel or on Cancel.
- The accepted Family figure: the Family phone space is 214 CSS px at 320 and 360 wide, above the 180 CSS px budget of
  Decision 5. The Family share targets are met there, so the budget is accepted as a limit, not a passed rule. At 390
  wide the space is 158 CSS px, within the budget.

## Trade-offs

- A visitor on a touch pointer who sends from Family Chat's keyboard now uses Shift+Enter, and Enter makes a new line. A
  visitor on a fine pointer sends with Enter, as in Codex chat. The hint names the shortcut for the visitor's pointer, and
  the Send button stays on every device.
- The Clear chat confirmation adds one click. It protects a whole conversation from a stray tap.
- Keeping the inert theme column is extra data that nothing reads. It keeps the migration and the rollback reader safe.
- Visitor Markdown can look different from what the visitor typed. The raw view is one click away.
- The Options panel adds one tap on a phone to reach the model and effort. The conversation gets the space instead.

## Consequences

- `chat_keys.js` and `chat_controls.js` are small client modules. Their unit tests and the e2e bindings prove the rules
  in a browser; the LiveView tests cover the server side only (LiveView does not run the confirmation).
- The Family and Codex rooms read the same key rule and the same hint, so they cannot drift apart.
- The six budget outlines in `chat.feature` and `family_chat.feature` carry `@fe-vitest-unit` and `@integration-exempt`
  (option (b), decided 2026-11-13). Vitest proves the declared CSS budgets in `codex_layout.steps.ts` and
  `family_chat_phone.steps.ts`. The e2e steps measure the numbers: `codex-phone-layout.steps.ts`,
  `codex_touch.steps.ts`, `codex_follow_layout.steps.ts`, `codex_header_access.steps.ts` and
  `family-chat-composer.steps.ts`. The integration exemption names its e2e alternative proof.
- Governance (`repo-governance/development/behaviour-driven-development.md`, line 31) says Unit has no exemption. No
  Unit exemption is applied to any row, so the outlines keep their Vitest proof. This change does not amend governance.
- Decision 8 items 5 to 7 of 004 no longer describe the shipped page. Read them with this record.

## Test layers

- Vitest (`apps/bnest-app/assets/test/behaviour`): the handlers in happy-dom, the declared CSS budgets, the absence of
  theme code.
- Unit (`apps/bnest-app/assets/test/unit`): `chat_keys.test.ts` for the key rule, and `composer.test.ts` for the Family
  draft rules. The Family mount reaches the key rule through `sendOnKey`, and the Family behaviour rows press keys
  through that mount.
- ExUnit (`apps/bnest-app/test/integration`): the confirmed clear, the page without a theme attribute, the Markdown
  markup of a visitor's message.
- e2e (`apps/bnest-app-fe-e2e/tests/steps`): the real keys, the confirmation, the raw toggle, the painted light page and
  the measured boxes at each viewport.
