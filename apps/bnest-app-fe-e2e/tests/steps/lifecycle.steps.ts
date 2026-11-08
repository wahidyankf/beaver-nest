import { createBdd } from "playwright-bdd";
import {
  closeBrowserContexts,
  instanceLifecycle,
} from "../support/active-instance";
import {
  restorePrimaryRoute,
  stopRoutedCandidates,
} from "../support/routed-rollout";
import { initializeBackupRepository } from "../support/backup-repository.mts";
import {
  backupRepositoryOf,
  needsBackupRepository,
  seedsAccountsForTags,
} from "../support/scenario-tags.mts";
import {
  accountPlan,
  phaseForTags,
  scenarioLabel,
  settleAll,
} from "../support/test-instance-lifecycle.mts";

const { After, Before } = createBdd();

// Each scenario gets its own instance: spawned and seeded here (ADR 001, sections 1 and 6 step 6), used by
// that scenario only, and deleted in After. Only a `@flat-primary` scenario starts from a flat instance.
Before(async ({ $testInfo }) => {
  const phase = phaseForTags($testInfo.tags);
  const instance = await instanceLifecycle().begin({
    label: scenarioLabel($testInfo.title),
    phase,
    // An `@open-setup` scenario seeds no account: its own setup submits them, and seeding one would close setup
    // (ADR 001, section 2).
    accounts: seedsAccountsForTags($testInfo.tags) ? accountPlan : () => [],
  });
  // A spawn leaves `backup-repository/` empty; a scenario that backs up needs it to be a git repository.
  if (needsBackupRepository($testInfo.tags)) {
    initializeBackupRepository(
      backupRepositoryOf(
        instance.environment.BNEST_STORAGE_CONFIG,
        instance.instanceId,
      ),
    );
  }
});

// The order matters: route the browser back first (it needs its page), close every browser context so no
// socket points at the instance, stop the rollout candidates that may still write to it, and only then
// delete it. Every step runs even when an earlier one fails, and a failed delete fails the scenario.
After(async ({ page, browser }) => {
  await settleAll([
    () => restorePrimaryRoute(page),
    () => closeBrowserContexts(browser),
    stopRoutedCandidates,
    () => instanceLifecycle().end(),
  ]);
});
