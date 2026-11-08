import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  currentInstanceEnvironment,
  instanceLifecycle,
} from "../support/active-instance.mts";
import {
  chatPayload,
  confirmImports,
  setSources,
} from "../support/centralized-data";
import { currentIdentities, userIdFor } from "../support/instance-identities";
import { importCount, instanceRecordState } from "../support/instance-records";
import {
  envelopeDigest,
  interruptedImportId,
  overwriteViolations,
} from "../support/interrupted-import-check.mts";

// Bindings for the interrupted-import scenario of centralized_data.feature. Split from centralized_data.steps.ts to keep
// each file within the lint line limit. The seed is flat-primary only, as the block below explains.

const { Given, Then, When } = createBdd();

let beforeImportCount = 0;
// The interrupted import the Given seeded: its identity, and its preserved envelope as it was seeded.
let interruptedImport:
  { importId: string; runtimeRoot: string; envelopeBefore: string } | undefined;

function adminId(): string {
  return userIdFor(currentIdentities().admin.username);
}

// The seed writes what an import leaves when it stops after preserving its envelope (ADR 001, section 2). The browser
// then holds the same payload, so the retry resumes that import identity. The baseline is taken after the seed, and
// it must be exactly the one envelope the seed wrote, so a seed that landed nowhere cannot pass the "no duplicate"
// check. This scenario is `@flat-primary`, the only phase that takes this seed kind.
Given(
  "a recognized import was interrupted after source preservation",
  async ({ page }) => {
    const seeded = await instanceLifecycle().seed("interrupted-import", {
      records: [
        {
          owner: currentIdentities().admin.username,
          kind: "browserImportInterrupted",
          value: {
            storageArea: "sessionStorage",
            storageKey: "bnest.chat.v1",
            payload: chatPayload,
          },
        },
      ],
    });
    expect(seeded.applied).toBe(true);
    const owner = adminId();
    const runtimeRoot = currentInstanceEnvironment().BNEST_RUNTIME_ROOT;
    const importId = interruptedImportId(
      owner,
      "sessionStorage",
      "bnest.chat.v1",
      chatPayload,
    );
    // Positive control: the seeded envelope exists under the derived identity, so a later match is about the retry.
    const envelopeBefore = envelopeDigest(runtimeRoot, owner, importId);
    expect(envelopeBefore).not.toBe("missing");
    interruptedImport = { importId, runtimeRoot, envelopeBefore };
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    beforeImportCount = importCount(owner);
    expect(beforeImportCount).toBe(1);
  },
);

When("the user retries that import", async ({ page }) => {
  await confirmImports(page);
});

Then("Bnest reuses its idempotent import identity", () => {
  expect(importCount(adminId())).toBe(beforeImportCount);
});

Then(
  "Bnest does not duplicate or overwrite accepted data",
  async ({ page }) => {
    await expect(
      page.getByText("Chat conversation: accepted and verified"),
    ).toBeVisible();
    const seededImport = interruptedImport;
    if (seededImport === undefined) {
      throw new Error("no interrupted import was seeded for this scenario");
    }
    const owner = adminId();
    const chat = instanceRecordState("chat", owner);
    const violations = overwriteViolations({
      expectedImportId: seededImport.importId,
      envelopeDigestBefore: seededImport.envelopeBefore,
      envelopeDigestAfter: envelopeDigest(
        seededImport.runtimeRoot,
        owner,
        seededImport.importId,
      ),
      importCountBefore: beforeImportCount,
      importCountAfter: importCount(owner),
      chatRecord: chat.present ? chat.record : null,
    });
    expect(violations).toEqual([]);
  },
);
