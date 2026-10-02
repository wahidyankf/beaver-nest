// Step bindings for the `@fe-vitest-unit` scenarios of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature -- every rule
// except the reply ones, which `family_chat_reply.steps.ts` binds.
//
// Every scenario runs the production room the way a browser does
// (`support/browser_room.ts`): the shipped template, a fresh copy of
// `js/family_chat.js` per page load, and the member's own input. A When acts
// the way a member or the network does -- typing, pressing a key, clicking,
// the connection going away -- and a Then reads what the room rendered or
// what reached the server, never a flag the room keeps about itself.

import {
  MESSAGE_PAGE_SIZE,
  CONTEXT_PAGE_SIZE,
} from "../../js/family_chat/page_source.js";
import { STATUS } from "../../js/family_chat/outbox.js";
import {
  AUTHENTICATED_MARKER,
  loadServiceWorker,
} from "../support/service_worker";
import {
  activate,
  activePage,
  announcement,
  clickOn,
  closePage,
  committedFor,
  computedStyleOf,
  createDevice,
  device,
  dropSockets,
  hasActivePage,
  hidden,
  isInView,
  isRendered,
  messageRows,
  namespaceOf,
  offsetInHistory,
  openHomePage,
  openRoomPage,
  otherMember,
  type Page,
  post,
  pressKey,
  reconnectSockets,
  reloadPage,
  requireRow,
  requireWorld,
  ROOM_SLUG,
  routeRevision,
  rowFor,
  scrollHistoryTo,
  sendThroughComposer,
  server,
  setDeviceOnline,
  setVisibility,
  settle,
  shownStatus,
  startWorld,
  tabOrder,
  typeText,
  useVisitor,
  visibleRemediation,
  visitor,
  waitFor,
  watchPendingRows,
  type Member,
} from "./support/browser_room";
import { recall, remember } from "./support/scenario_memory";

export type StepContext = Record<string, unknown>;

export type StepHandler = (
  context: StepContext,
  ...args: string[]
) => StepContext | Promise<StepContext>;

export interface StepDefinition {
  readonly expression: string;
  readonly handler: StepHandler;
}

const registry: StepDefinition[] = [];

function step(
  expression: string,
  handler: (...args: string[]) => void | Promise<void>,
): void {
  registry.push({
    expression,
    handler: async (context, ...args) => {
      await handler(...args);
      return context;
    },
  });
}

export function familyChatSteps(): readonly StepDefinition[] {
  return registry;
}

function expect(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const AYAH = (): Member => otherMember("Ayah");

/** The family room as a visitor usually finds it: a few messages in. */
function ensureConversation(count = 3): void {
  if (server().messages.length > 0) return;
  for (let index = 1; index <= count; index += 1) {
    post({ body: `Kabar rumah ${index}`, sender: AYAH() });
  }
}

/** Opens the room, closing whatever this member had open first. */
async function reopenRoom(pathname: string): Promise<Page> {
  if (hasActivePage()) await closePage(activePage());
  return openRoomPage({ pathname });
}

function clientMessageId(): string {
  return recall<string>("clientMessageId");
}

function attemptsFor(id: string, memberId = visitor().id) {
  return server().sendAttempts.filter(
    (attempt) =>
      attempt.clientMessageId === id && attempt.memberId === memberId,
  );
}

/** Lets the page's timers run up to their next deadline. */
function advanceToNextTimer(page: Page): number {
  const due = page.clock.nextDueAt();
  if (due === null) throw new Error("the page has no timer pending");
  page.clock.advance(due - page.clock.now());
  return due;
}

async function expectStatus(id: string, expected: string): Promise<void> {
  if (expected === STATUS.SENT) {
    await waitFor(() => {
      const committed = committedFor(id);
      return (
        committed !== undefined &&
        rowFor(committed.id) !== null &&
        rowFor(id) === null
      );
    }, `message ${id} to reach Sent`).catch((error: unknown) => {
      const row = rowFor(id);
      throw new Error(
        `${String(error)} (attempts ${JSON.stringify(attemptsFor(id).map((attempt) => attempt.outcome))}, ` +
          `committed ${String(committedFor(id)?.id)}, pending row ${row ? JSON.stringify(shownStatus(row)) : "none"})`,
      );
    });
    const committed = committedFor(id);
    const copies = messageRows().filter(
      (row) => row.dataset["messageId"] === committed?.id,
    );
    expect(copies.length === 1, `Sent rendered ${copies.length} copies`);
    expect(
      activePage().elements.outboxStatus.textContent === "",
      "the outbox status still reports a pending send",
    );
    return;
  }
  await waitFor(
    () => rowFor(id) !== null && shownStatus(requireRow(id)) === expected,
    `message ${id} to show ${JSON.stringify(expected)}`,
  );
}

// --- Background ---------------------------------------------------------------

step("an approved user is logged in", () => {
  startWorld();
});

// --- Rule: Online send status ---------------------------------------------------

step("a visitor opens {string}", async (pathname) => {
  ensureConversation();
  await openRoomPage({ pathname });
});

step("the visitor sends the family chat message {string}", async (body) => {
  const id = await sendThroughComposer(body);
  expect(id !== null, "the room refused to queue the message");
  remember("clientMessageId", id);
});

step("the message shows status {string}", async (expected) => {
  await expectStatus(clientMessageId(), expected);
});

step("the message reaches status {string}", async (expected) => {
  await expectStatus(clientMessageId(), expected);
});

step(
  "the visitor sends a family chat message during a retryable network failure",
  async () => {
    // Every send fails to get an answer, the way an aborted fetch does;
    // the rest of the page keeps working.
    server().setSendOutcome(visitor().id, "offline");
    const id = await sendThroughComposer("On my way");
    expect(id !== null, "the room refused to queue the message");
    remember("clientMessageId", id);
  },
);

step("the network recovers", async () => {
  server().setSendOutcome(visitor().id, "commit");
  setDeviceOnline(activePage().device, true);
  await settle();
});

step(
  "the visitor sends a family chat message the server rejects as invalid",
  async () => {
    server().setSendOutcome(visitor().id, { code: "VALIDATION_FAILED" });
    const id = await sendThroughComposer("On my way");
    expect(id !== null, "the room refused to queue the message");
    remember("clientMessageId", id);
  },
);

step("no automatic retry is attempted", async () => {
  const page = activePage();
  const id = clientMessageId();
  await expectStatus(id, STATUS.FAILED);
  page.clock.advance(10 * 60 * 1000);
  await settle();
  const attempts = attemptsFor(id).length;
  expect(
    attempts === 1,
    `the room sent the rejected message ${attempts} times`,
  );
  expect(
    shownStatus(requireRow(id)) === STATUS.FAILED,
    "the rejected message left Couldn't send on its own",
  );
});

// --- Rule: Bounded per-room outbox ------------------------------------------------

step(
  "the visitor's outbox for this room already holds {int} queued messages",
  async (count) => {
    // Offline, every message the member writes waits in the queue.
    setDeviceOnline(activePage().device, false);
    for (let index = 1; index <= Number(count); index += 1) {
      const id = await sendThroughComposer(`Waiting message ${index}`);
      expect(id !== null, `message ${index} was refused before the cap`);
    }
    const stored = device().persistence.rowsFor(namespaceOf(visitor())).length;
    expect(stored === Number(count), `the queue holds ${stored} messages`);
  },
);

step("the visitor attempts to queue one more message", async () => {
  remember("refusedId", await sendThroughComposer("One more message"));
});

step("the new message is not queued", () => {
  const page = activePage();
  expect(
    recall<string | null>("refusedId") === null,
    "the 101st message was queued",
  );
  const stored = device().persistence.rowsFor(namespaceOf(visitor())).length;
  expect(stored === 100, `the queue holds ${stored} messages`);
  const pending = messageRows().filter(
    (row) => row.dataset["deliveryState"] !== "committed",
  ).length;
  expect(pending === 100, `the room shows ${pending} queued messages`);
  expect(
    page.elements.input.value === "One more message",
    "the refused draft was not kept in the input",
  );
});

step("the composer explains the retry-or-discard remediation", () => {
  const shown = visibleRemediation().toLowerCase();
  expect(
    shown.includes("retry") && shown.includes("discard"),
    `the composer shows ${JSON.stringify(visibleRemediation())}`,
  );
});

// --- Rule: Resume, online reaction, backoff, and seven-day expiry ------------------

const DAY_MS = 24 * 60 * 60 * 1000;

/** A row a tab closed earlier left in IndexedDB, in the shape it writes. */
function seedQueuedRow(id: string, body: string, createdAgoMs: number): void {
  const now = device().now;
  device().persistence.seed(namespaceOf(visitor()), {
    clientMessageId: id,
    body,
    status: STATUS.RETRYING,
    attempt: 1,
    retryCount: 0,
    createdAt: now - createdAgoMs,
    nextRetryAt: now + 1000,
  });
  remember("clientMessageId", id);
}

step("the visitor has a queued message left over from a closed session", () => {
  ensureConversation();
  seedQueuedRow(
    "a1b2c3d4-0000-4000-8000-000000000040",
    "Left over from a closed tab",
    60_000,
  );
});

step("the visitor reopens {string}", async (pathname) => {
  await reopenRoom(pathname);
});

step(
  "the queued message resumes toward Sent without visitor action",
  async () => {
    // Nothing is pressed between the reopen and this: whatever sends it is
    // the room's own resume.
    await expectStatus(clientMessageId(), STATUS.SENT);
    expect(
      attemptsFor(clientMessageId()).length >= 1,
      "the left-over message never reached the server",
    );
  },
);

step("a fresh visitor opens {string}", async (pathname) => {
  useVisitor(otherMember("Fresh"));
  ensureConversation();
  await openRoomPage({ pathname });
});

step("the visitor reloads the page", async () => {
  await reloadPage();
});

step("the message is durably queued for a closed tab to resume", async () => {
  const id = clientMessageId();
  const stored = device()
    .persistence.rowsFor(namespaceOf(visitor()))
    .some((row) => row.clientMessageId === id);
  expect(stored, "the queued message has no row in the device's outbox store");
  // This page's runtime is new: the row it renders came back from storage.
  await waitFor(() => rowFor(id) !== null, "the reloaded room to show it");
  expect(
    shownStatus(requireRow(id)) !== STATUS.SENT,
    "the message was already sent",
  );
});

step("a queued message is waiting on its backoff timer", async () => {
  server().setSendOutcome(visitor().id, "offline");
  const id = await sendThroughComposer("Waiting for the network");
  expect(id !== null, "the room refused to queue the message");
  remember("clientMessageId", id);
  await expectStatus(id ?? "", STATUS.RETRYING);
  const page = activePage();
  const due = page.clock.nextDueAt();
  expect(
    due !== null && due > page.clock.now(),
    "the message has no backoff timer pending",
  );
  remember("attemptsBefore", attemptsFor(id ?? "").length);
});

step("the browser reports the {string} event", async (name) => {
  const page = activePage();
  server().setSendOutcome(visitor().id, "commit");
  remember("eventAt", page.clock.now());
  page.window.dispatchEvent(new page.window.Event(name));
  await settle();
});

step("the queued message becomes immediately eligible for retry", () => {
  const attempts = attemptsFor(clientMessageId());
  const before = recall<number>("attemptsBefore");
  expect(
    attempts.length === before + 1,
    `the online event led to ${attempts.length - before} attempts`,
  );
  expect(
    attempts.at(-1)?.at === recall<number>("eventAt"),
    "the retry waited for its backoff timer instead",
  );
});

step("a queued message fails five times with a retryable result", async () => {
  const page = activePage();
  server().setSendOutcome(visitor().id, "offline");
  const id = await sendThroughComposer("Retry me");
  expect(id !== null, "the room refused to queue the message");
  const waits: number[] = [];
  for (let failure = 1; failure <= 5; failure += 1) {
    await waitFor(
      () => attemptsFor(id ?? "").length === failure,
      `attempt ${failure}`,
    );
    await expectStatus(id ?? "", STATUS.RETRYING);
    const failedAt = attemptsFor(id ?? "").at(-1)?.at ?? 0;
    const due = page.clock.nextDueAt();
    if (due === null)
      throw new Error(`no retry was scheduled after failure ${failure}`);
    waits.push(due - failedAt);
    if (failure < 5) advanceToNextTimer(page);
  }
  remember("waits", waits);
});

step(
  "each wait follows 1, 2, 4, 8, and 16 seconds with bounded jitter and no wait exceeding 60 seconds",
  () => {
    const waits = recall<number[]>("waits");
    const bases = [1000, 2000, 4000, 8000, 16_000];
    expect(waits.length === bases.length, `measured ${waits.length} waits`);
    bases.forEach((base, index) => {
      const wait = waits[index] ?? Number.NaN;
      expect(
        wait >= base * 0.8 && wait <= base * 1.2 && wait <= 60_000,
        `wait ${index + 1} was ${wait} ms against a ${base} ms base`,
      );
    });
  },
);

step(
  "the visitor has a queued message created more than seven days ago",
  () => {
    ensureConversation();
    seedQueuedRow(
      "a1b2c3d4-0000-4000-8000-000000000044",
      "Queued a week ago",
      7 * DAY_MS + 60_000,
    );
    remember(
      "seededRows",
      device().persistence.rowsFor(namespaceOf(visitor())),
    );
  },
);

step("the message is not automatically retried", async () => {
  const id = clientMessageId();
  await expectStatus(id, STATUS.FAILED);
  activePage().clock.advance(10 * 60 * 1000);
  await settle();
  const attempts = attemptsFor(id).length;
  expect(attempts === 0, `the expired message was sent ${attempts} times`);
});

function manualControl(id: string, role: string): HTMLButtonElement {
  const control = requireRow(id).querySelector<HTMLButtonElement>(
    `[data-role="${role}"]`,
  );
  if (!control || !isRendered(control) || control.disabled) {
    throw new Error(`message ${id} offers no ${role}`);
  }
  return control;
}

step("the visitor can still manually retry or discard it", async () => {
  const id = clientMessageId();
  // Retrying sends it.
  await clickOn(manualControl(id, "family-chat-message-retry"));
  await expectStatus(id, STATUS.SENT);
  expect(attemptsFor(id).length === 1, "the retry sent it more than once");

  // The same expired message on another visit: discarding drops it, from
  // the room and from the device, without sending it.
  await closePage(activePage());
  for (const row of recall<Record<string, unknown>[]>("seededRows")) {
    device().persistence.seed(namespaceOf(visitor()), row);
  }
  device().now += 1;
  const page = await openRoomPage();
  await expectStatus(id, STATUS.FAILED);
  // Discarding removes the only copy, so the room asks first; a member who
  // says no keeps the message.
  page.confirmAnswer = false;
  await clickOn(manualControl(id, "family-chat-message-discard"));
  await settle();
  expect(page.dialogs.length === 1, "discarding did not ask for confirmation");
  expect(rowFor(id) !== null, "a declined discard still removed the message");
  page.confirmAnswer = true;
  await clickOn(manualControl(id, "family-chat-message-discard"));
  await waitFor(
    () => rowFor(id) === null,
    "the discarded message to leave the room",
  );
  await settle();
  const stored = device()
    .persistence.rowsFor(namespaceOf(visitor()))
    .some((row) => row.clientMessageId === id);
  expect(!stored, "the discarded message is still stored on the device");
  expect(attemptsFor(id).length === 1, "discarding sent the message");
});

// --- Rule: Auth expiry pause and logout isolation -----------------------------------

step("a message is queued", async () => {
  server().setSendOutcome(visitor().id, "offline");
  const id = await sendThroughComposer("Queued before the session ended");
  expect(id !== null, "the room refused to queue the message");
  remember("clientMessageId", id);
  await expectStatus(id ?? "", STATUS.RETRYING);
});

step("the visitor's authentication expires", async () => {
  const page = activePage();
  server().setSendOutcome(visitor().id, { code: "UNAUTHENTICATED" });
  const before = attemptsFor(clientMessageId()).length;
  advanceToNextTimer(page);
  await waitFor(
    () => attemptsFor(clientMessageId()).length === before + 1,
    "the retry the server refuses as unauthenticated",
  );
  await settle();
  remember("attemptsAtExpiry", attemptsFor(clientMessageId()).length);
});

step("queue draining pauses for that namespace", async () => {
  const page = activePage();
  // The server would take it again now; a paused queue does not ask.
  server().setSendOutcome(visitor().id, "commit");
  page.clock.advance(10 * 60 * 1000);
  await settle();
  const attempts = attemptsFor(clientMessageId()).length;
  expect(
    attempts === recall<number>("attemptsAtExpiry"),
    `the queue kept sending after expiry (${attempts} attempts)`,
  );
  expect(
    page.elements.room?.dataset["connectionState"] === "auth-expired",
    "the room does not show that the session expired",
  );
});

step("no other user's session drains that queued message", async () => {
  const id = clientMessageId();
  const owner = visitor();
  await closePage(activePage());
  // Another member signs in on the same device, with the same IndexedDB.
  const other = otherMember("Bunda");
  const page = await openRoomPage({ member: other });
  page.clock.advance(10 * 60 * 1000);
  await settle(page);
  const drained = server().sendAttempts.filter(
    (attempt) =>
      attempt.clientMessageId === id && attempt.memberId !== owner.id,
  );
  expect(drained.length === 0, "another member's session sent the message");
  expect(rowFor(id, page) === null, "another member's room shows the message");
  const stillQueued = device()
    .persistence.rowsFor(namespaceOf(owner))
    .some((row) => row.clientMessageId === id);
  expect(stillQueued, "the owner's queued message was lost");
  expect(messageRows(page).length > 0, "the other member's room did not load");
});

step("the visitor logs out", async () => {
  const id = clientMessageId();
  const stored = device()
    .persistence.rowsFor(namespaceOf(visitor()))
    .some((row) => row.clientMessageId === id);
  expect(stored, "nothing was queued on the device before logging out");
  // This session had notifications on, so logout has a binding to end.
  server().pushBindings.set(visitor().id, true);
  await closePage(activePage());
  const home = await openHomePage();
  const button = home.document.querySelector<HTMLButtonElement>(
    "form button[type=submit]",
  );
  if (!button) throw new Error("the home page has no Log out button");
  await clickOn(button);
  await waitFor(() => home.navigatedTo === "/login", "the log-out to submit");
});

step("the visitor's local outbox namespace is cleared", () => {
  const rows = device().persistence.rowsFor(namespaceOf(visitor()));
  expect(rows.length === 0, `${rows.length} queued messages survived logout`);
});

step("the current session's Web Push subscription is disabled", () => {
  expect(
    server().logouts.includes(visitor().id),
    "the log-out never reached the server",
  );
  expect(
    server().pushBindings.get(visitor().id) === false,
    "the session's push binding is still enabled",
  );
});

// --- Rules: Reconnect across Caddy promotion, visibility, handshake ---------------------

const CONTROL_TOPIC = "__absinthe__:control";

step(
  "a visitor opens {string} with the socket connected to the current slot",
  async (pathname) => {
    ensureConversation();
    const page = await openRoomPage({ pathname });
    const [socket] = page.sockets;
    expect(
      page.sockets.length === 1 &&
        socket?.record.open === true &&
        socket.record.joins.includes(CONTROL_TOPIC),
      "the room did not connect its socket to the current slot",
    );
    remember("priorSockets", [...page.sockets]);
    remember("firstRow", messageRows(page)[0]);
  },
);

step("Caddy promotes a replacement slot", async () => {
  const page = activePage();
  // A send that is waiting on its retry timer when the cutover happens.
  server().setSendOutcome(visitor().id, "offline");
  const queued = await sendThroughComposer("Queued across the promotion");
  expect(queued !== null, "the room refused to queue the message");
  await expectStatus(queued ?? "", STATUS.RETRYING);
  remember("clientMessageId", queued);
  server().setSendOutcome(visitor().id, "commit");

  remember("priorSockets", [...page.sockets]);
  remember("wireMark", server().wire.length);
  remember("promotedAt", performance.now());
  // Caddy's reload closes the prior slot's upstream connection; a message
  // committed in that gap never reaches this socket.
  dropSockets(page);
  remember(
    "gapMessage",
    post({ body: "Sent during the cutover", sender: AYAH() }),
  );
  // phoenix reconnects to whatever Caddy now routes.
  reconnectSockets(page);
  await Promise.resolve();
  await Promise.resolve();
  // The queued send's retry comes due while the room is catching up.
  page.clock.advance(60_000);
  await settle();
});

step("the prior-slot socket closes", () => {
  for (const socket of recall<Page["sockets"]>("priorSockets")) {
    expect(
      socket.record.disconnects >= 1 && !socket.record.open,
      "the prior slot's socket was never closed by the room",
    );
  }
});

step(
  "the browser subscribes on the promoted slot and completes catch-up within ten seconds",
  async () => {
    const page = activePage();
    const prior = recall<Page["sockets"]>("priorSockets");
    const fresh = page.sockets.filter((socket) => !prior.includes(socket));
    expect(
      fresh.some(
        (socket) =>
          socket.record.open && socket.record.joins.includes(CONTROL_TOPIC),
      ),
      "no socket on the promoted slot joined the control channel",
    );
    const gap = recall<{ id: string }>("gapMessage");
    await waitFor(
      () => rowFor(gap.id) !== null,
      "the gap message to be caught up",
    );
    const elapsed = performance.now() - recall<number>("promotedAt");
    expect(elapsed < 10_000, `catch-up took ${Math.round(elapsed)} ms`);
  },
);

step("any queued send drains only after catch-up completes", async () => {
  const id = clientMessageId();
  await expectStatus(id, STATUS.SENT);
  const wire = server().wire.slice(recall<number>("wireMark"));
  const caughtUp = wire.findIndex(
    (event) =>
      event.kind === "response" &&
      event.operation === "FamilyChatMessages" &&
      event.variables["afterId"] !== undefined,
  );
  const sent = wire.findIndex(
    (event) =>
      event.kind === "request" &&
      event.operation === "SendFamilyChatMessage" &&
      event.variables["clientMessageId"] === id,
  );
  expect(caughtUp !== -1, "the room never ran a catch-up query");
  expect(sent !== -1, "the queued send never drained");
  expect(sent > caughtUp, "the queued send went out before catch-up finished");
});

step("the page does not reload", () => {
  const page = activePage();
  const loads = requireWorld().pages.filter(
    (candidate) =>
      candidate.kind === "room" && candidate.member === page.member,
  ).length;
  expect(loads === 1, `the room was loaded ${loads} times`);
  const firstRow = recall<HTMLElement>("firstRow");
  expect(
    firstRow.isConnected && page.document.contains(firstRow),
    "the room's rendered history was replaced",
  );
});

step(
  "the tab is backgrounded with its connection silently dropped",
  async () => {
    const page = activePage();
    remember("priorSockets", [...page.sockets]);
    setVisibility(page, "hidden");
    dropSockets(page);
    await settle();
  },
);

step("the tab becomes visible again", async () => {
  setVisibility(activePage(), "visible");
  await settle();
});

step("a fresh socket connection replaces the prior one", () => {
  const page = activePage();
  const prior = recall<Page["sockets"]>("priorSockets");
  for (const socket of prior) {
    expect(!socket.record.open, "the dead connection is still the room's");
  }
  const fresh = page.sockets.filter(
    (socket) => !prior.includes(socket) && socket.record.open,
  );
  expect(
    fresh.length === 1 &&
      fresh[0]?.record.joins.includes(CONTROL_TOPIC) === true,
    `${fresh.length} fresh sockets joined the control channel`,
  );
});

step(
  "no phx_join frame is sent for any topic other than the control channel",
  () => {
    const joins = activePage().sockets.flatMap((socket) => socket.record.joins);
    const others = joins.filter((topic) => topic !== CONTROL_TOPIC);
    expect(others.length === 0, `the room joined ${JSON.stringify(others)}`);
    // The positive control: the capture saw the joins that did happen,
    // before the drop and after the resume.
    const control = joins.filter((topic) => topic === CONTROL_TOPIC).length;
    expect(control >= 2, `only ${control} control-channel joins were seen`);
  },
);

// --- Rule: Experience release candidate proof ------------------------------------

step("Caddy has promoted the flag-enabled experience candidate", () => {
  routeRevision(true);
});

step("two members each open {string}", async (pathname) => {
  ensureConversation();
  const first = await openRoomPage({ pathname });
  const second = await openRoomPage({
    pathname,
    member: otherMember("Bunda"),
    device: createDevice(),
  });
  remember("members", [first, second]);
});

step("one member queues a message while offline", async () => {
  const [first] = recall<Page[]>("members");
  if (!first) throw new Error("no members opened the room");
  activate(first);
  setDeviceOnline(first.device, false);
  const id = await sendThroughComposer("Queued while offline", first);
  expect(id !== null, "the room refused to queue the message");
  remember("clientMessageId", id);
  await expectStatus(id ?? "", STATUS.WAITING);
});

step("the offline member's connection is restored", async () => {
  const [first] = recall<Page[]>("members");
  if (!first) throw new Error("no members opened the room");
  activate(first);
  remember("wireMark", server().wire.length);
  setDeviceOnline(first.device, true);
  await settle(first);
});

step(
  "the offline member's queued message drains exactly once after reconnect",
  async () => {
    const id = clientMessageId();
    await expectStatus(id, STATUS.SENT);
    const committed = server().sendAttempts.filter(
      (attempt) =>
        attempt.clientMessageId === id && attempt.outcome === "commit",
    );
    expect(
      committed.length === 1,
      `the message was sent ${committed.length} times`,
    );
    const stored = server().messages.filter(
      (message) => message.body === "Queued while offline",
    );
    expect(stored.length === 1, `the server holds ${stored.length} copies`);
    const after = server()
      .wire.slice(recall<number>("wireMark"))
      .some(
        (event) =>
          event.operation === "SendFamilyChatMessage" &&
          event.variables["clientMessageId"] === id,
      );
    expect(after, "the message did not drain after the reconnect");
  },
);

step("neither member sees a duplicate or lost message", async () => {
  const expected = server()
    .messages.map((message) => message.id)
    .sort();
  for (const page of recall<Page[]>("members")) {
    activate(page);
    await settle(page);
    const shown = messageRows(page)
      .map((row) => row.dataset["messageId"] ?? "")
      .sort();
    expect(
      JSON.stringify(shown) === JSON.stringify(expected),
      `${page.member.displayName} sees ${JSON.stringify(shown)}, the room holds ${JSON.stringify(expected)}`,
    );
  }
});

// --- Rule: Resuming at the last read position -------------------------------------

const READ_KEY_PREFIX = "bnest.family-chat.last-read";

function storedReadPosition(member: Member = visitor()): string | null {
  return (
    device().readStorage.get(`${READ_KEY_PREFIX}.${member.id}.${ROOM_SLUG}`) ??
    null
  );
}

/** Reads to the end of the conversation the way a member does: scrolling. */
async function readDownToNewest(page: Page): Promise<void> {
  for (let pass = 0; pass < 20; pass += 1) {
    scrollHistoryTo(page, Number.MAX_SAFE_INTEGER);
    await settle(page);
    const rows = messageRows(page);
    if (
      storedReadPosition(page.member) === server().newest()?.id &&
      rows.at(-1)?.dataset["messageId"] === server().newest()?.id
    ) {
      return;
    }
  }
  throw new Error("reading down never reached the newest message");
}

async function readUpToNewest(): Promise<void> {
  const page = await openRoomPage();
  await readDownToNewest(page);
  remember("readUpTo", storedReadPosition());
  await closePage(page);
}

function divider(page: Page = activePage()): HTMLElement | null {
  return page.elements.list.querySelector<HTMLElement>(
    '[data-role="family-chat-unread-divider"]',
  );
}

function postFromAyah(count: number, label: string): string {
  let first = "";
  for (let index = 1; index <= count; index += 1) {
    const message = post({ body: `${label} ${index}`, sender: AYAH() });
    if (index === 1) first = message.id;
  }
  return first;
}

step(
  "the family chat holds more earlier messages than one context page",
  () => {
    postFromAyah(CONTEXT_PAGE_SIZE + 10, "Earlier message");
  },
);

step("the visitor has read the family chat up to a known message", async () => {
  ensureConversation(5);
  await readUpToNewest();
});

step("{int} newer messages arrived while the visitor was away", (count) => {
  remember("firstUnread", postFromAyah(Number(count), "While away"));
});

step("the first unread message is the first message in view", () => {
  const marker = divider();
  expect(marker !== null, "the room shows no unread marker");
  const first = marker?.nextElementSibling as HTMLElement | null;
  expect(
    first?.dataset["messageId"] === recall<string>("firstUnread"),
    `the first message after the marker is ${String(first?.dataset["messageId"])}`,
  );
  expect(
    first !== null && isInView(first),
    "the first unread message is not in view",
  );
  // The marker sits at the top of the view, unless the unread messages are
  // too few to scroll that far -- then the room rests at the bottom.
  const history = activePage().elements.history;
  const atBottom =
    history.scrollHeight - history.scrollTop - history.clientHeight <= 1;
  const markerOffset = offsetInHistory(marker as HTMLElement);
  expect(
    markerOffset >= 0 && (markerOffset <= 100 || atBottom),
    `the marker sits ${markerOffset} px into the view`,
  );
});

step("an unread marker separates the read messages from the new ones", () => {
  const marker = divider();
  if (!marker) throw new Error("the room shows no unread marker");
  const before = marker.previousElementSibling as HTMLElement | null;
  const after = marker.nextElementSibling as HTMLElement | null;
  expect(
    before?.dataset["messageId"] === recall<string>("readUpTo"),
    `the marker follows ${String(before?.dataset["messageId"])}`,
  );
  expect(
    after?.dataset["messageId"] === recall<string>("firstUnread"),
    `the marker precedes ${String(after?.dataset["messageId"])}`,
  );
});

function rowsAboveMarker(): number {
  const marker = divider();
  if (!marker) throw new Error("the room shows no unread marker");
  let count = 0;
  for (
    let node = marker.previousElementSibling;
    node;
    node = node.previousElementSibling
  ) {
    count += 1;
  }
  return count;
}

step(
  "one bounded page of earlier messages is loaded above the unread marker",
  () => {
    const above = rowsAboveMarker();
    // The bound itself, as a number: compared with the module's own constant
    // it would follow any change to it.
    expect(
      above === 20,
      `${above} earlier messages are loaded above the marker`,
    );
  },
);

step("older history can still be loaded on request", async () => {
  const page = activePage();
  const before = rowsAboveMarker();
  expect(
    !page.elements.loadOlder.disabled && isRendered(page.elements.loadOlder),
    "the room offers no way to load older history",
  );
  await clickOn(page.elements.loadOlder);
  await settle();
  expect(rowsAboveMarker() > before, "loading older history added nothing");
});

step("the visitor has read every message in the family chat", async () => {
  ensureConversation(5);
  await readUpToNewest();
});

step("the newest message is in view", async () => {
  await settle();
  const newest = server().newest();
  if (!newest) throw new Error("the room holds no messages");
  const row = rowFor(newest.id);
  expect(row !== null, "the newest message is not rendered");
  expect(row !== null && isInView(row), "the newest message is not in view");
});

step("no unread marker is shown", () => {
  expect(divider() === null, "the room shows an unread marker");
});

step("the visitor has never opened the family chat on this device", () => {
  ensureConversation(5);
  expect(
    storedReadPosition() === null,
    "this device already has a read position",
  );
});

step("the visitor scrolls down to the newest message", async () => {
  await readDownToNewest(activePage());
});

step(
  "the visitor left more unread messages behind than one page holds",
  async () => {
    ensureConversation(5);
    await readUpToNewest();
    remember(
      "firstUnread",
      postFromAyah(MESSAGE_PAGE_SIZE + 10, "Unread backlog"),
    );
  },
);

step("{string} offers a way back to the newest message", (label) => {
  const button = activePage().elements.newMessages;
  expect(
    isRendered(button) && button.textContent?.trim() === label,
    `the room shows ${JSON.stringify(button.textContent?.trim())} hidden=${String(button.hidden)}`,
  );
  expect(
    rowFor(server().newest()?.id ?? "") === null,
    "the newest message was already loaded",
  );
});

step("the visitor jumps to the newest message", async () => {
  await clickOn(activePage().elements.newMessages);
  await settle();
});

// --- Rule: Composer focus and keyboard ---------------------------------------------

step(
  "a visitor opens {string} with focus in the composer",
  async (pathname) => {
    ensureConversation(30);
    const page = await openRoomPage({ pathname });
    await clickOn(page.elements.input);
    expect(
      page.document.activeElement === page.elements.input,
      "the message input did not take focus",
    );
  },
);

/** Counts every time focus leaves the input, or lands on Send. */
function watchComposerFocus(page: Page): {
  inputBlurs: number;
  sendFocuses: number;
} {
  const counts = { inputBlurs: 0, sendFocuses: 0 };
  page.elements.input.addEventListener("blur", () => (counts.inputBlurs += 1));
  page.elements.send.addEventListener("focus", () => (counts.sendFocuses += 1));
  return counts;
}

step("the visitor sends {string} through the composer", async (body) => {
  const page = activePage();
  if (page.document.activeElement !== page.elements.input) {
    await clickOn(page.elements.input);
  }
  const counts = watchComposerFocus(page);
  const queued = watchPendingRows(page);
  typeText(body);
  const press = await clickOn(page.elements.send);
  await waitFor(() => queued.length > 0, "the message to be queued");
  remember("clientMessageId", queued[0]);
  remember("sendPress", { ...press, counts });
  await settle();
});

step("the composer still holds keyboard focus", () => {
  const page = activePage();
  expect(
    page.document.activeElement === page.elements.input,
    `focus is on ${String((page.document.activeElement as HTMLElement | null)?.dataset?.["role"] ?? page.document.activeElement?.tagName)}`,
  );
});

step(
  "activating the send control never takes focus from the message input",
  () => {
    const press = recall<{
      focusMoved: boolean;
      counts: { inputBlurs: number; sendFocuses: number };
    }>("sendPress");
    expect(!press.focusMoved, "pressing Send moved focus");
    expect(press.counts.sendFocuses === 0, "the Send button took focus");
    expect(press.counts.inputBlurs === 0, "the message input lost focus");
  },
);

step("the composer is empty and ready for the next message", () => {
  const { input, send } = activePage().elements;
  expect(
    input.value === "",
    `the input still holds ${JSON.stringify(input.value)}`,
  );
  expect(!input.disabled && !send.disabled, "the composer is disabled");
});

step("the visitor submits {string} with the Enter key", async (body) => {
  const queued = watchPendingRows();
  typeText(body);
  await pressKey("Enter");
  await waitFor(() => queued.length > 0, "Enter to queue the message");
  remember("clientMessageId", queued[0]);
  await settle();
});

step(
  "the visitor presses Shift and Enter while writing {string}",
  async (text) => {
    typeText(text);
    await pressKey("Enter", { shiftKey: true });
    await settle();
    remember("draftText", text);
  },
);

step("the composer holds an unsent multi-line draft", () => {
  const text = recall<string>("draftText");
  const value = activePage().elements.input.value;
  expect(
    value.startsWith(text) && value.split("\n").length >= 2,
    `the input holds ${JSON.stringify(value)}`,
  );
  const sent = server().sendAttempts.some((attempt) =>
    attempt.body.includes(text),
  );
  expect(!sent, "Shift+Enter sent the draft");
});

step(
  "a visitor opens {string} scrolled to a known older message",
  async (pathname) => {
    // More than the first page holds, so there is older history to load.
    postFromAyah(MESSAGE_PAGE_SIZE + 30, "History");
    const page = await openRoomPage({ pathname });
    scrollHistoryTo(page, 0);
    await settle();
    const known = messageRows(page)[0];
    if (!known || !isInView(known))
      throw new Error("no older message is in view");
    expect(
      !isInView(requireRow(server().newest()?.id ?? "")),
      "the newest message is still in view",
    );
    remember("knownRow", known);
  },
);

step("the visitor's own message is in view", async () => {
  const id = clientMessageId();
  await waitFor(() => committedFor(id) !== undefined, "the message to commit");
  await settle();
  const row = rowFor(committedFor(id)?.id ?? "") ?? rowFor(id);
  expect(
    row !== null && isInView(row),
    "the visitor's own message is not in view",
  );
});

// --- Rule: Scroll anchor and live-region announcements --------------------------------

step("the visitor loads an older history page", async () => {
  const page = activePage();
  const known = recall<HTMLElement>("knownRow");
  remember("knownOffset", offsetInHistory(known));
  const before = messageRows(page).length;
  await clickOn(page.elements.loadOlder);
  await waitFor(
    () => messageRows(page).length > before,
    "older messages to load",
  );
  await settle();
});

step(
  "the previously visible message remains at the same visual position",
  () => {
    const known = recall<HTMLElement>("knownRow");
    expect(
      known.isConnected,
      "the message the visitor was reading was replaced",
    );
    const drift = Math.abs(
      offsetInHistory(known) - recall<number>("knownOffset"),
    );
    expect(drift <= 1, `the message the visitor was reading moved ${drift} px`);
  },
);

step(
  "another member's message arrives away from the bottom of the scroll position",
  async () => {
    const page = activePage();
    scrollHistoryTo(page, 0);
    await settle();
    remember("scrollTopBefore", page.elements.history.scrollTop);
    remember(
      "arrival",
      post({ body: "Sudah di jalan pulang", sender: AYAH() }),
    );
    await settle();
  },
);

step("a live-region announcement names the new message", async () => {
  const arrival = recall<{ body: string }>("arrival");
  await waitFor(
    () =>
      announcement().includes(arrival.body) && announcement().includes("Ayah"),
    "the arrival to be announced",
  );
});

step("focus remains in the composer", () => {
  const page = activePage();
  expect(
    page.document.activeElement === page.elements.input,
    "focus moved away from the message input",
  );
});

step("{string} is shown instead of auto-scrolling", (label) => {
  const page = activePage();
  const button = page.elements.newMessages;
  expect(
    isRendered(button) && button.textContent?.trim() === label,
    `the room shows ${JSON.stringify(button.textContent?.trim())}`,
  );
  expect(
    page.elements.history.scrollTop === recall<number>("scrollTopBefore"),
    "the history scrolled on its own",
  );
  const arrival = recall<{ id: string }>("arrival");
  const row = rowFor(arrival.id);
  expect(row === null || !isInView(row), "the arrival was scrolled into view");
});

// --- Rule: Push permission UX and no authenticated caching ------------------------------

step("the visitor's device reports push state {string}", (state) => {
  device().push = state as ReturnType<typeof device>["push"];
  if (state === "subscription active") {
    server().pushBindings.set(visitor().id, true);
  }
});

step("the room shows the control {string}", async (text) => {
  const control = activePage().elements.pushControl;
  await waitFor(
    () => control.textContent?.trim() === text,
    `the push control to read ${JSON.stringify(text)} (it reads ${JSON.stringify(control.textContent?.trim())})`,
  );
});

step(
  "a visitor opens {string} with an active push subscription",
  async (pathname) => {
    device().push = "subscription active";
    server().pushBindings.set(visitor().id, true);
    ensureConversation();
    const page = await openRoomPage({ pathname });
    await waitFor(
      () => !hidden(page.elements.pushDisable),
      "the room to offer turning notifications off",
    );
  },
);

step("the visitor selects {string}", async (label) => {
  const page = activePage();
  const control = [page.elements.pushControl, page.elements.pushDisable].find(
    (button) => button.textContent?.trim() === label && isRendered(button),
  );
  if (!control) throw new Error(`the room offers no ${JSON.stringify(label)}`);
  await clickOn(control);
  await settle();
});

step("a visitor opens {string} and exchanges messages", async (pathname) => {
  const worker = loadServiceWorker();
  await worker.install();
  await worker.activate();
  device().serviceWorker = worker;
  ensureConversation();
  await openRoomPage({ pathname });
  const id = await sendThroughComposer("Cache probe from the visitor");
  expect(id !== null, "the room refused to queue the message");
  await expectStatus(id ?? "", STATUS.SENT);
  const reply = post({ body: "Cache probe from Ayah", sender: AYAH() });
  await waitFor(() => rowFor(reply.id) !== null, "the reply to arrive");
});

step("the service worker's Cache Storage is inspected", async () => {
  const worker = device().serviceWorker;
  if (!worker) throw new Error("no service worker is installed");
  const entries: { pathname: string; body: string }[] = [];
  for (const cache of worker.caches.values()) {
    for (const [pathname, response] of cache) {
      entries.push({ pathname, body: await response.clone().text() });
    }
  }
  remember("cacheEntries", entries);
});

const STATIC_PATH = /^\/(?:assets|images)\/|^\/manifest\.webmanifest$/u;

step("it contains only static build assets", () => {
  const entries = recall<{ pathname: string }[]>("cacheEntries");
  // The positive control: the worker did cache what the page loaded.
  expect(
    entries.some((entry) => entry.pathname.startsWith("/assets/")),
    "Cache Storage holds no build asset at all",
  );
  const other = entries.filter((entry) => !STATIC_PATH.test(entry.pathname));
  expect(
    other.length === 0,
    `Cache Storage holds ${JSON.stringify(other.map((e) => e.pathname))}`,
  );
});

step("it contains no navigation response, message, or GraphQL response", () => {
  const entries = recall<{ pathname: string; body: string }[]>("cacheEntries");
  const leaked = entries.filter(
    (entry) =>
      entry.pathname === "/" ||
      entry.pathname.startsWith("/family-chat") ||
      entry.pathname.startsWith("/api/") ||
      entry.body.includes(AUTHENTICATED_MARKER) ||
      entry.body.includes("Cache probe"),
  );
  expect(
    leaked.length === 0,
    `Cache Storage holds ${JSON.stringify(leaked.map((e) => e.pathname))}`,
  );
});

// --- Rule: Responsive and accessible presentation ------------------------------------

step("the viewport is set to {string}", (description) => {
  const match = /(\d+)x(\d+)(?:\s+(\d+)%)?/u.exec(description);
  if (!match) throw new Error(`unreadable viewport ${description}`);
  const zoom = match[3] ? Number(match[3]) / 100 : 1;
  // Zooming in is a narrower viewport in CSS pixels.
  device().viewport = {
    width: Math.round(Number(match[1]) / zoom),
    height: Math.round(Number(match[2]) / zoom),
    deviceScaleFactor: zoom,
  };
});

/** Every control a member can operate in the room, outside the message rows. */
function roomControls(page: Page): HTMLElement[] {
  const room = page.elements.room;
  if (!room) throw new Error("no room is rendered");
  const controls = [
    ...room.querySelectorAll<HTMLElement>(
      "a[href], button, textarea, input, select",
    ),
  ].filter(
    (element) =>
      !(element as HTMLButtonElement).disabled &&
      isRendered(element) &&
      element.closest('[data-role="family-chat-message"]') === null,
  );
  const stop = page.elements.list.querySelector<HTMLElement>(
    '[data-role="family-chat-message"][tabindex="0"]',
  );
  return stop ? [...controls, stop] : controls;
}

function hasFocusRing(element: HTMLElement): boolean {
  const style = computedStyleOf(element);
  const outline =
    style.outlineStyle !== "" &&
    style.outlineStyle !== "none" &&
    Number.parseFloat(style.outlineWidth || "0") > 0;
  const shadow = style.boxShadow !== "" && style.boxShadow !== "none";
  return outline || shadow;
}

step(
  "every control is reachable by keyboard with a visible focus indicator",
  async () => {
    const page = activePage();
    const sheet = page.document.styleSheets[0];
    expect(
      sheet !== undefined && sheet.cssRules.length > 0,
      "the shipped stylesheet did not load into the page",
    );
    const controls = roomControls(page);
    expect(controls.length > 0, "the room renders no controls");
    (page.document.activeElement as HTMLElement | null)?.blur?.();
    const reached = new Set<HTMLElement>();
    const order = tabOrder(page.document);
    for (let press = 0; press < order.length + 1; press += 1) {
      await pressKey("Tab");
      const focused = page.document.activeElement as HTMLElement | null;
      if (!focused) continue;
      reached.add(focused);
      expect(
        focused.matches(":focus-visible") && hasFocusRing(focused),
        `${focused.dataset["role"] ?? focused.tagName} shows no focus indicator ` +
          `(:focus-visible ${String(focused.matches(":focus-visible"))}, outline ` +
          `${JSON.stringify(computedStyleOf(focused).outline)})`,
      );
    }
    const missed = controls.filter((control) => !reached.has(control));
    expect(
      missed.length === 0,
      `Tab never reaches ${JSON.stringify(missed.map((control) => control.dataset["role"] ?? control.tagName))}`,
    );
  },
);

/** A length the browser would resolve without layout, in CSS pixels. */
function absoluteLength(value: string): number | null {
  const match = /^(-?[\d.]+)(px|rem|em)$/u.exec(value.trim());
  if (!match) return null;
  const amount = Number(match[1]);
  return match[2] === "px" ? amount : amount * 16;
}

step("no horizontal page scroll is present", () => {
  const page = activePage();
  const viewport = page.device.viewport.width;
  const win = page.window;
  expect(
    win.innerWidth === viewport,
    `the page is ${win.innerWidth} px wide, not ${viewport}`,
  );
  const room = page.elements.room;
  if (!room) throw new Error("no room is rendered");
  const roomStyle = win.getComputedStyle(room as never);
  expect(
    roomStyle.display !== "",
    "the shipped stylesheet did not apply to the room",
  );
  const tooWide: string[] = [];
  for (const element of [room, ...room.querySelectorAll<HTMLElement>("*")]) {
    if (!isRendered(element)) continue;
    const style = win.getComputedStyle(element as never);
    for (const property of ["width", "min-width"] as const) {
      const length = absoluteLength(style.getPropertyValue(property));
      if (length !== null && length > viewport) {
        tooWide.push(
          `${element.className || element.tagName} ${property}: ${style.getPropertyValue(property)}`,
        );
      }
    }
  }
  expect(
    tooWide.length === 0,
    `wider than the ${viewport} px viewport: ${tooWide.join(", ")}`,
  );
});
