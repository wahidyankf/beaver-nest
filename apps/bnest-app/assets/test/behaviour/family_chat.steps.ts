// Step bindings for the `@fe-vitest-unit` scenarios of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature.
//
// These scenarios cover the IndexedDB outbox, retry backoff, reconnect/
// reconcile, push-permission UI, and scroll/accessibility concerns that
// tech-doc 006's Proof Matrix marks "Not applicable"/"Not layout-capable"
// for the combined BE unit/integration column and "Required" for frontend
// Vitest instead (see learnings.md and test/behaviour/verify.exs's
// `BnestApp.Behaviour.FeVitestUnitScope` for the BE-side half of this split).
//
// Every handler below imports the real (not-yet-built) production module
// with a *dynamic* `import()` inside the handler body, not a static
// top-level import. That keeps RED failures scoped to the scenario that
// actually exercises the missing module, instead of one module-load error
// failing the whole file — mirroring how the Elixir unit/integration
// drivers fail per scenario via UndefinedFunctionError, not at compile time.

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

function step(expression: string, handler: StepHandler): void {
  registry.push({ expression, handler });
}

export function familyChatSteps(): readonly StepDefinition[] {
  return registry;
}

// --- Shared helpers -------------------------------------------------------

// Resolved against this module's own URL (not the Vite/vite-node root) so
// dynamic `import()` finds the sibling js/ tree regardless of the runner's
// working directory or root option; a plain relative specifier here would
// resolve against vite-node's root instead of this file's location.
const ROOM_JS = new URL("../../js/family_chat.js", import.meta.url).href;
const OUTBOX_JS = new URL("../../js/family_chat/outbox.js", import.meta.url)
  .href;
const RECONNECT_JS = new URL(
  "../../js/family_chat/reconnect.js",
  import.meta.url,
).href;

interface RoomOptions {
  scrolledToOlderMessage?: boolean;
  focusInComposer?: boolean;
  socketConnectedToCurrentSlot?: boolean;
  activePushSubscription?: boolean;
  exchangesMessages?: boolean;
  devicePushState?: string | undefined;
}

async function openRoom(
  context: StepContext,
  path: string,
  options: RoomOptions = {},
): Promise<StepContext> {
  const { initRoom } = await import(/* @vite-ignore */ ROOM_JS);
  const room = await initRoom(path, { user: context["user"], ...options });
  return { ...context, room, roomPath: path };
}

function requireRoom(context: StepContext): Record<string, unknown> {
  const room = context["room"];
  if (room === undefined || room === null) {
    throw new Error("no room has been opened yet in this scenario");
  }
  return room as Record<string, unknown>;
}

// --- Background -------------------------------------------------------

step("an approved user is logged in", (context) => {
  // Synthetic identity only; never a real production account
  // (test-identities.md iron rule).
  return { ...context, user: { id: "test-user-family-chat", approved: true } };
});

// --- Rule: Online send status ------------------------------------------

step("a visitor opens {string}", async (context, path) =>
  // Forwards a push state set by a prior "the visitor's device reports push
  // state ..." Given step (the Scenario Outline at "The room shows the
  // correct push permission state" has no specialized opening wording of
  // its own, unlike the other room-option variants below).
  openRoom(context, path, {
    devicePushState: context["devicePushState"] as string | undefined,
  }),
);

step(
  "the visitor sends the family chat message {string}",
  async (context, body) => {
    const room = requireRoom(context);
    const outbox = room["outbox"] as {
      send: (body: string) => Promise<string>;
    };
    const clientMessageId = await outbox.send(body);
    return { ...context, lastClientMessageId: clientMessageId };
  },
);

step("the message shows status {string}", async (context, expected) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    status: (clientMessageId: string) => string;
  };
  const status = outbox.status(context["lastClientMessageId"] as string);
  if (status !== expected) {
    throw new Error(`expected status "${expected}", got "${status}"`);
  }
  return context;
});

step("the message reaches status {string}", async (context, expected) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    waitForStatus: (clientMessageId: string, status: string) => Promise<string>;
  };
  const status = await outbox.waitForStatus(
    context["lastClientMessageId"] as string,
    expected,
  );
  if (status !== expected) {
    throw new Error(`expected status "${expected}", got "${status}"`);
  }
  return context;
});

step(
  "the visitor sends a family chat message during a retryable network failure",
  async (context) => {
    const room = requireRoom(context);
    const outbox = room["outbox"] as {
      send: (body: string, opts: Record<string, unknown>) => Promise<string>;
    };
    const clientMessageId = await outbox.send("On my way", {
      simulateNetworkFailure: "retryable",
    });
    return { ...context, lastClientMessageId: clientMessageId };
  },
);

step("the network recovers", async (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as { reportOnline: () => void };
  outbox.reportOnline();
  return context;
});

step(
  "the visitor sends a family chat message the server rejects as invalid",
  async (context) => {
    const room = requireRoom(context);
    const outbox = room["outbox"] as {
      send: (body: string, opts: Record<string, unknown>) => Promise<string>;
    };
    const clientMessageId = await outbox.send("On my way", {
      simulateNetworkFailure: "non-retryable",
    });
    return { ...context, lastClientMessageId: clientMessageId };
  },
);

step("no automatic retry is attempted", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    retryCount: (clientMessageId: string) => number;
  };
  const retries = outbox.retryCount(context["lastClientMessageId"] as string);
  if (retries !== 0) {
    throw new Error(`expected zero automatic retries, got ${retries}`);
  }
  return context;
});

// --- Rule: Bounded per-room outbox --------------------------------------

step(
  "the visitor's outbox for this room already holds {int} queued messages",
  async (context, count) => {
    const room = requireRoom(context);
    const outbox = room["outbox"] as {
      fillWithQueuedMessages: (count: number) => Promise<void>;
    };
    await outbox.fillWithQueuedMessages(Number(count));
    return context;
  },
);

step("the visitor attempts to queue one more message", async (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    send: (body: string) => Promise<string | null>;
  };
  const clientMessageId = await outbox.send("one more message");
  return { ...context, lastClientMessageId: clientMessageId };
});

step("the new message is not queued", (context) => {
  if (context["lastClientMessageId"] !== null) {
    throw new Error("expected the outbox to reject the 101st message");
  }
  return context;
});

step("the composer explains the retry-or-discard remediation", (context) => {
  const room = requireRoom(context);
  const composer = room["composer"] as { remediationMessage: string | null };
  if (!composer.remediationMessage) {
    throw new Error("expected the composer to show a remediation message");
  }
  return context;
});

// --- Rule: Resume, online reaction, backoff, and seven-day expiry ------

step(
  "the visitor has a queued message left over from a closed session",
  async (context) => {
    const { seedQueuedMessage } = await import(/* @vite-ignore */ OUTBOX_JS);
    const seed = await seedQueuedMessage({ ageMs: 0 });
    return { ...context, seededMessage: seed };
  },
);

step("the visitor reopens {string}", async (context, path) =>
  openRoom(context, path),
);

step(
  "the queued message resumes toward Sent without visitor action",
  async (context) => {
    const room = requireRoom(context);
    const outbox = room["outbox"] as {
      status: (clientMessageId: string) => string;
    };
    const seed = context["seededMessage"] as { clientMessageId: string };
    const status = outbox.status(seed.clientMessageId);
    if (status === "queued" || status === "Not sent") {
      throw new Error("expected the queue to resume draining automatically");
    }
    return context;
  },
);

step("a queued message is waiting on its backoff timer", async (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    queueWithPendingBackoff: () => Promise<string>;
  };
  const clientMessageId = await outbox.queueWithPendingBackoff();
  return { ...context, lastClientMessageId: clientMessageId };
});

step("the browser reports the {string} event", (context, eventName) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    reportBrowserEvent: (name: string) => void;
  };
  outbox.reportBrowserEvent(eventName);
  return context;
});

step("the queued message becomes immediately eligible for retry", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    nextRetryEtaMs: (clientMessageId: string) => number;
  };
  const eta = outbox.nextRetryEtaMs(context["lastClientMessageId"] as string);
  if (eta > 0) {
    throw new Error(`expected an immediate retry, next attempt in ${eta}ms`);
  }
  return context;
});

step(
  "a queued message fails five times with a retryable result",
  async (context) => {
    const room = requireRoom(context);
    const outbox = room["outbox"] as {
      failRepeatedly: (times: number) => Promise<number[]>;
    };
    const delaysMs = await outbox.failRepeatedly(5);
    return { ...context, observedBackoffDelaysMs: delaysMs };
  },
);

step(
  "each wait follows 1, 2, 4, 8, and 16 seconds with bounded jitter and no wait exceeding 60 seconds",
  (context) => {
    const baseDelaysMs = [1_000, 2_000, 4_000, 8_000, 16_000];
    const delaysMs = context["observedBackoffDelaysMs"] as number[];
    delaysMs.forEach((delayMs, index) => {
      const base = baseDelaysMs[index];
      if (base === undefined) {
        throw new Error(
          `no expected base delay defined for attempt ${index + 1}`,
        );
      }
      const min = base * 0.8;
      const max = Math.min(base * 1.2, 60_000);
      if (delayMs < min || delayMs > max) {
        throw new Error(
          `attempt ${index + 1}: expected ${delayMs}ms within [${min}, ${max}]ms`,
        );
      }
    });
    return context;
  },
);

step(
  "the visitor has a queued message created more than seven days ago",
  async (context) => {
    const { seedQueuedMessage } = await import(/* @vite-ignore */ OUTBOX_JS);
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
    const seed = await seedQueuedMessage({ ageMs: sevenDaysMs + 1_000 });
    return { ...context, seededMessage: seed };
  },
);

step("the message is not automatically retried", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    isAutoRetrying: (clientMessageId: string) => boolean;
  };
  const seed = context["seededMessage"] as { clientMessageId: string };
  if (outbox.isAutoRetrying(seed.clientMessageId)) {
    throw new Error("expected automatic retry to have stopped at seven days");
  }
  return context;
});

step("the visitor can still manually retry or discard it", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    canManuallyRetryOrDiscard: (clientMessageId: string) => boolean;
  };
  const seed = context["seededMessage"] as { clientMessageId: string };
  if (!outbox.canManuallyRetryOrDiscard(seed.clientMessageId)) {
    throw new Error("expected manual retry/discard to remain available");
  }
  return context;
});

// --- Rule: Auth expiry pause and logout isolation ------------------------

step("a message is queued", async (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as { send: (body: string) => Promise<string> };
  const clientMessageId = await outbox.send("queued before expiry");
  return { ...context, lastClientMessageId: clientMessageId };
});

step("the visitor's authentication expires", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as { reportAuthExpired: () => void };
  outbox.reportAuthExpired();
  return context;
});

step("queue draining pauses for that namespace", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as { isDraining: () => boolean };
  if (outbox.isDraining()) {
    throw new Error("expected draining to be paused after auth expiry");
  }
  return context;
});

step("no other user's session drains that queued message", async (context) => {
  requireRoom(context); // validates a room was opened; the value itself is unused here
  const { initRoom } = await import(/* @vite-ignore */ ROOM_JS);
  const otherUserRoom = await initRoom(context["roomPath"] as string, {
    user: { id: "test-user-family-chat-other", approved: true },
  });
  const otherOutbox = (otherUserRoom as Record<string, unknown>)["outbox"] as {
    status: (clientMessageId: string) => string;
  };
  const status = otherOutbox.status(context["lastClientMessageId"] as string);
  if (status !== "not-found") {
    throw new Error("expected the other session's namespace to be isolated");
  }
  return context;
});

step("the visitor logs out", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as { logout: () => void };
  outbox.logout();
  return context;
});

step("the visitor's local outbox namespace is cleared", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as { isCleared: () => boolean };
  if (!outbox.isCleared()) {
    throw new Error("expected the outbox namespace to be cleared on logout");
  }
  return context;
});

step("the current session's Web Push subscription is disabled", (context) => {
  const room = requireRoom(context);
  const push = room["push"] as { isDisabled: () => boolean };
  if (!push.isDisabled()) {
    throw new Error("expected the push subscription to be disabled on logout");
  }
  return context;
});

// --- Rule: Reconnect across Caddy promotion ------------------------------

step(
  "a visitor opens {string} with the socket connected to the current slot",
  async (context, path) =>
    openRoom(context, path, { socketConnectedToCurrentSlot: true }),
);

step("Caddy promotes a replacement slot", async (context) => {
  const { promoteSlot } = await import(/* @vite-ignore */ RECONNECT_JS);
  const room = requireRoom(context);
  await promoteSlot(room["reconnect"]);
  return context;
});

step("the prior-slot socket closes", (context) => {
  const room = requireRoom(context);
  const reconnect = room["reconnect"] as { priorSlotClosed: () => boolean };
  if (!reconnect.priorSlotClosed()) {
    throw new Error("expected the prior-slot socket to close");
  }
  return context;
});

step(
  "the browser subscribes on the promoted slot and completes catch-up within ten seconds",
  (context) => {
    const room = requireRoom(context);
    const reconnect = room["reconnect"] as { catchUpDurationMs: () => number };
    const durationMs = reconnect.catchUpDurationMs();
    if (durationMs > 10_000) {
      throw new Error(`catch-up took ${durationMs}ms, expected <= 10000ms`);
    }
    return context;
  },
);

step("any queued send drains only after catch-up completes", (context) => {
  const room = requireRoom(context);
  const reconnect = room["reconnect"] as {
    drainedBeforeCatchUp: () => boolean;
  };
  if (reconnect.drainedBeforeCatchUp()) {
    throw new Error("expected the queue to wait for catch-up before draining");
  }
  return context;
});

step("the page does not reload", (context) => {
  const room = requireRoom(context);
  const reconnect = room["reconnect"] as { pageReloaded: () => boolean };
  if (reconnect.pageReloaded()) {
    throw new Error("expected reconnect to avoid a full page reload");
  }
  return context;
});

// --- Rule: Experience release candidate proof -----------------------------
//
// The candidate/Caddy promotion itself is release infrastructure this layer
// cannot observe (see this file's header); "Caddy has promoted the
// flag-enabled experience candidate" is a no-op here, mirroring how
// `reconnect.js`'s `subscribeFirstStep` treats an unbound `resubscribe` as a
// pure ordering guarantee for FE_UNIT's document-less room. What this layer
// *can* prove is the outbox's own draft/offline-queue/reconnect/exact-once
// behavior, and that a second session's outbox namespace never observes the
// first session's queued message -- cross-client delivery itself (the other
// member's UI actually rendering it) is bnest-app-fe-e2e:test:e2e's job.

step(
  "Caddy has promoted the flag-enabled experience candidate",
  (context) => context,
);

step("two members each open {string}", async (context, path) => {
  const withMemberA = await openRoom(context, path);
  const { initRoom } = await import(/* @vite-ignore */ ROOM_JS);
  const memberBRoom = await initRoom(path, {
    user: {
      id: "test-user-family-chat-experience-release-other",
      approved: true,
    },
  });
  return { ...withMemberA, memberBRoom };
});

step("one member queues a message while offline", async (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    send: (body: string, opts: Record<string, unknown>) => Promise<string>;
  };
  const clientMessageId = await outbox.send(
    "Queued before the experience release promotion",
    {
      simulateNetworkFailure: "retryable",
    },
  );
  return { ...context, lastClientMessageId: clientMessageId };
});

step("the offline member's connection is restored", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as { reportOnline: () => void };
  outbox.reportOnline();
  return context;
});

step(
  "the offline member's queued message drains exactly once after reconnect",
  async (context) => {
    const room = requireRoom(context);
    const outbox = room["outbox"] as {
      waitForStatus: (
        clientMessageId: string,
        status: string,
      ) => Promise<string>;
    };
    const clientMessageId = context["lastClientMessageId"] as string;
    const status = await outbox.waitForStatus(clientMessageId, "Sent");
    if (status !== "Sent") {
      throw new Error(`expected status "Sent", got "${status}"`);
    }
    return context;
  },
);

step("neither member sees a duplicate or lost message", (context) => {
  const room = requireRoom(context);
  const outbox = room["outbox"] as {
    status: (clientMessageId: string) => string;
  };
  const clientMessageId = context["lastClientMessageId"] as string;
  if (outbox.status(clientMessageId) !== "Sent") {
    throw new Error(
      "expected the sending member's outbox to hold exactly one Sent copy",
    );
  }

  const memberBRoom = context["memberBRoom"] as Record<string, unknown>;
  const memberBOutbox = memberBRoom["outbox"] as {
    status: (clientMessageId: string) => string;
  };
  if (memberBOutbox.status(clientMessageId) !== "not-found") {
    throw new Error(
      "expected the other member's outbox namespace to be isolated from this send",
    );
  }
  return context;
});

// --- Rule: Scroll anchor and live-region announcements -------------------

step(
  "a visitor opens {string} scrolled to a known older message",
  async (context, path) =>
    openRoom(context, path, { scrolledToOlderMessage: true }),
);

step("the visitor loads an older history page", async (context) => {
  const room = requireRoom(context);
  const store = room["store"] as { loadOlderPage: () => Promise<void> };
  await store.loadOlderPage();
  return context;
});

step(
  "the previously visible message remains at the same visual position",
  (context) => {
    const room = requireRoom(context);
    const store = room["store"] as { scrollAnchorPreserved: () => boolean };
    if (!store.scrollAnchorPreserved()) {
      throw new Error("expected the scroll anchor to be preserved");
    }
    return context;
  },
);

step(
  "a visitor opens {string} with focus in the composer",
  async (context, path) => openRoom(context, path, { focusInComposer: true }),
);

step(
  "another member's message arrives away from the bottom of the scroll position",
  async (context) => {
    const room = requireRoom(context);
    const store = room["store"] as {
      receiveRemoteMessage: (opts: Record<string, unknown>) => Promise<void>;
    };
    await store.receiveRemoteMessage({ scrolledAwayFromBottom: true });
    return context;
  },
);

step("a live-region announcement names the new message", (context) => {
  const room = requireRoom(context);
  const store = room["store"] as {
    lastLiveRegionAnnouncement: () => string | null;
  };
  if (!store.lastLiveRegionAnnouncement()) {
    throw new Error("expected a live-region announcement");
  }
  return context;
});

step("focus remains in the composer", (context) => {
  const room = requireRoom(context);
  const store = room["store"] as { focusMovedFromComposer: () => boolean };
  if (store.focusMovedFromComposer()) {
    throw new Error("expected focus to remain in the composer");
  }
  return context;
});

step("{string} is shown instead of auto-scrolling", (context, label) => {
  const room = requireRoom(context);
  const store = room["store"] as {
    newMessagesIndicatorLabel: () => string | null;
  };
  if (store.newMessagesIndicatorLabel() !== label) {
    throw new Error(`expected the indicator label "${label}"`);
  }
  return context;
});

// --- Rule: Push permission UX and no authenticated caching ---------------

step(
  "the visitor's device reports push state {string}",
  async (context, deviceState) => {
    return { ...context, devicePushState: deviceState };
  },
);

step("the room shows the control {string}", (context, controlText) => {
  const room = requireRoom(context);
  const push = room["push"] as { controlText: () => string };
  const actual = push.controlText();
  if (actual !== controlText) {
    throw new Error(`expected control text "${controlText}", got "${actual}"`);
  }
  return context;
});

step(
  "a visitor opens {string} with an active push subscription",
  async (context, path) =>
    openRoom(context, path, { activePushSubscription: true }),
);

step("the visitor selects {string}", async (context, control) => {
  const room = requireRoom(context);
  const push = room["push"] as { select: (control: string) => Promise<void> };
  await push.select(control);
  return context;
});

step("a visitor opens {string} and exchanges messages", async (context, path) =>
  openRoom(context, path, { exchangesMessages: true }),
);

step("the service worker's Cache Storage is inspected", async (context) => {
  const room = requireRoom(context);
  const push = room["push"] as {
    inspectCacheStorage: () => Promise<{ entries: string[] }>;
  };
  const inspection = await push.inspectCacheStorage();
  return { ...context, cacheStorageEntries: inspection.entries };
});

step("it contains only static build assets", (context) => {
  const entries = context["cacheStorageEntries"] as string[];
  const nonStatic = entries.filter((entry) => !entry.startsWith("/assets/"));
  if (nonStatic.length > 0) {
    throw new Error(
      `expected only static assets, found ${nonStatic.join(", ")}`,
    );
  }
  return context;
});

step(
  "it contains no navigation response, message, or GraphQL response",
  (context) => {
    const entries = context["cacheStorageEntries"] as string[];
    const forbidden = entries.filter(
      (entry) =>
        entry === "/" ||
        entry.includes("family-chat") ||
        entry.includes("/api/graphql"),
    );
    if (forbidden.length > 0) {
      throw new Error(
        `expected no authenticated entries, found ${forbidden.join(", ")}`,
      );
    }
    return context;
  },
);

// --- Rule: Responsive and accessible presentation -------------------------

step("the viewport is set to {string}", (context, viewport) => {
  return { ...context, viewport };
});

step(
  "every control is reachable by keyboard with a visible focus indicator",
  async (context) => {
    const { initRoom } = await import(/* @vite-ignore */ ROOM_JS);
    const room = await initRoom("/family-chat/ruang-keluarga", {
      user: context["user"],
      viewport: context["viewport"],
    });
    const accessibility = (room as Record<string, unknown>)[
      "accessibility"
    ] as {
      keyboardReachable: () => boolean;
    };
    if (!accessibility.keyboardReachable()) {
      throw new Error("expected every control to be keyboard-reachable");
    }
    return { ...context, room };
  },
);

step("no horizontal page scroll is present", (context) => {
  const room = requireRoom(context);
  const accessibility = room["accessibility"] as {
    hasHorizontalScroll: () => boolean;
  };
  if (accessibility.hasHorizontalScroll()) {
    throw new Error("expected no horizontal page scroll");
  }
  return context;
});
