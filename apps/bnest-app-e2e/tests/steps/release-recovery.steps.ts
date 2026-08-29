import {
  expect,
  type Browser,
  type BrowserContext,
  type Page,
  type TestInfo,
} from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import { isolatedLoadIdentities } from "../support/test-identity";

type RecoveryClient = {
  context: BrowserContext;
  draft: string;
  group: number;
  page: Page;
  route: string;
};

const { Given, Then, When } = createBdd();
let recoveryClients: RecoveryClient[] = [];
let expectedRecoveryClientCount = 0;
let expectedRecoveryGroupCount = 0;

Given(
  "{int} synthetic visitors across {int} recovery groups have distinct drafts on {string}",
  async (
    { page, $testInfo },
    clientCount: number,
    groupCount: number,
    route: string,
  ) => {
    recoveryClients = await prepareRecoveryClients(
      page,
      $testInfo,
      clientCount,
      groupCount,
      route,
    );
    expectedRecoveryClientCount = clientCount;
    expectedRecoveryGroupCount = groupCount;
  },
);

When(
  "every recovery-group visitor reconnects after a deployment",
  async ({ page }) => {
    void page;
    try {
      await setRecoveryClientConnections(false);
      await setRecoveryClientConnections(true);
    } catch (error) {
      await closeRecoveryClients();
      throw error;
    }
  },
);

Then(
  "every recovery-group visitor keeps its route and draft",
  async ({ page }) => {
    void page;
    try {
      expect(recoveryClients).toHaveLength(expectedRecoveryClientCount);
      expect(new Set(recoveryClients.map(({ group }) => group)).size).toBe(
        expectedRecoveryGroupCount,
      );
      await Promise.all(
        recoveryClients.flatMap((client) => [
          expect(client.page).toHaveURL((url) => url.pathname === client.route),
          expect(client.page.getByLabel("Message")).toHaveValue(client.draft),
        ]),
      );
    } finally {
      await closeRecoveryClients();
    }
  },
);

Then(
  "the in-progress turn resumes once or fails safely without duplication",
  async ({ page }) => {
    const response = page.locator("[data-role=assistant-message]").last();
    const alert = page.getByRole("alert");
    const fallbackMessage =
      "The previous response was interrupted. Your transcript is preserved; send a new message to continue.";

    await expect
      .poll(async () => {
        if (
          (await alert.count()) === 1 &&
          (await alert.textContent())?.trim() === fallbackMessage
        ) {
          return "failed-safely";
        }

        const completed =
          (await response.getAttribute("data-streaming")) === "false";
        const updateCount = Number(
          await response.getAttribute("data-update-count"),
        );
        return completed && updateCount >= 2 ? "resumed" : "pending";
      })
      .toMatch(/^(failed-safely|resumed)$/u);

    await expect(
      page.locator("[data-role=user-message]", {
        hasText: "Resume after deployment",
      }),
    ).toHaveCount(1);
  },
);

async function prepareRecoveryClients(
  page: Page,
  testInfo: TestInfo,
  clientCount: number,
  groupCount: number,
  route: string,
): Promise<RecoveryClient[]> {
  const browser = page.context().browser();
  if (!browser) throw new Error("Browser fixture is unavailable");
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== "string") {
    throw new TypeError("The E2E project must declare a string baseURL");
  }
  if (clientCount < 1 || groupCount < 1 || groupCount > clientCount) {
    throw new RangeError(
      "Recovery clients and groups must be positive and groups cannot exceed clients",
    );
  }

  const identities = isolatedLoadIdentities(testInfo, clientCount);
  const attempts = await Promise.allSettled(
    identities.map((identity, index) =>
      createRecoveryClient(
        browser,
        new URL(baseURL).origin,
        identity,
        index,
        groupCount,
        route,
      ),
    ),
  );
  const clients = attempts.flatMap((attempt) =>
    attempt.status === "fulfilled" ? [attempt.value] : [],
  );
  const failure = attempts.find((attempt) => attempt.status === "rejected");
  if (failure?.status !== "rejected") return clients;
  await Promise.all(clients.map(({ context }) => context.close()));
  throw failure.reason;
}

async function createRecoveryClient(
  browser: Browser,
  origin: string,
  identity: { password: string; username: string },
  index: number,
  groupCount: number,
  route: string,
): Promise<RecoveryClient> {
  const context = await browser.newContext({ baseURL: origin });
  try {
    const page = await context.newPage();
    await login(page, identity);
    await page.goto(route);
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    const draft = `Recovery draft ${index + 1}`;
    await page.getByLabel("Message").fill(draft);
    return { context, draft, group: (index % groupCount) + 1, page, route };
  } catch (error) {
    await context.close();
    throw error;
  }
}

async function setRecoveryClientConnections(connected: boolean): Promise<void> {
  await Promise.all(
    recoveryClients.map(({ page }) =>
      page.evaluate((shouldConnect) => {
        const liveSocket = (
          window as unknown as {
            liveSocket: { connect: () => void; disconnect: () => void };
          }
        ).liveSocket;
        if (shouldConnect) liveSocket.connect();
        else liveSocket.disconnect();
      }, connected),
    ),
  );
  const expectedClass = connected ? /phx-connected/u : /phx-client-error/u;
  await Promise.all(
    recoveryClients.map(({ page }) =>
      expect(page.locator("[data-phx-main]")).toHaveClass(expectedClass),
    ),
  );
}

async function closeRecoveryClients(): Promise<void> {
  const clients = recoveryClients;
  recoveryClients = [];
  expectedRecoveryClientCount = 0;
  expectedRecoveryGroupCount = 0;
  await Promise.all(clients.map(({ context }) => context.close()));
}
