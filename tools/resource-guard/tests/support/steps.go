package support

import (
	"context"

	"github.com/cucumber/godog"
	"github.com/wahidyankf/beaver-nest/tools/resource-guard/tests/contract"
)

var _ contract.Driver = (*Driver)(nil)

// Initialize binds the shared contract to the resource-guard driver.
func (driver *Driver) Initialize(scenarioContext *godog.ScenarioContext) {
	scenarioContext.Before(func(ctx context.Context, _ *godog.Scenario) (context.Context, error) {
		driver.reset()
		return ctx, nil
	})
	functions := []any{
		driver.threeHealthy,
		driver.assessAdmission,
		driver.requireAdmitted,
		driver.requireStorageBlocked,
		driver.swapGrowth,
		driver.assessPressure,
		func() error { return driver.requireReason("swap-warning") },
		driver.compressorGrowth,
		func() error { return driver.requireReason("compressor-warning") },
		driver.liveLease,
		driver.waitLease,
		driver.requireDeferred,
		driver.inherited,
		driver.successfulChild,
		driver.requirePreserved,
		driver.givenAdmitted,
		driver.child17,
		driver.require17,
		driver.criticalChild,
		driver.observeCritical,
		driver.requireShed,
		driver.compiledBinary,
		driver.jsonStatus,
		driver.requireStatus,
		driver.invalidRun,
		driver.requireValidation,
		func() error { return driver.summary(0) },
		driver.assessSummary,
		driver.requireAccepted,
		driver.releaseHost,
		driver.assessRelease,
		driver.requireReleaseCPU,
		driver.failedSummary,
		driver.assessSummary,
		driver.requireRejected,
		driver.nxBuildConfiguration,
		driver.inspectBuildCaching,
		driver.requireBuildCacheDisabled,
		driver.e2eHarness,
		driver.inspectE2ELifecycle,
		driver.requireE2ECleanup,
		driver.historicalGenerations,
		driver.runCurrentBootstrap,
		driver.requireRetention,
		driver.goLintConfiguration,
		driver.inspectLintEnforcement,
		driver.requireExhaustiveLint,
		driver.requirePackageDocumentation,
		driver.requireModuleScopedLint,
		driver.gherkinAdapterContract,
		driver.inspectBehaviourCoverage,
		driver.requireStrictAdapters,
		driver.requireApprovedExemptions,
		driver.requireSerialCompliance,
		driver.requireE2EPlacement,
		driver.smallRunner,
		driver.requireConstrained,
		driver.tinyMachine,
		driver.requireMinimal,
		driver.exhaustedDisk,
		driver.strictTransaction,
		driver.requireReplan,
		driver.linuxCgroupCapacity,
		driver.collectLinuxEvidence,
		driver.requireFourGiB,
		driver.linuxWithoutSwap,
		driver.requireSwapUnavailable,
		driver.linuxPSIWarning,
		driver.requirePSIWarning,
		driver.invalidExplicitConfig,
		driver.statusWithConfig,
		driver.requireConfigExit,
		driver.artifactPolicy,
		driver.inspectArtifactPolicy,
		driver.requirePrivateArtifacts,
		driver.requireExampleTracked,
	}
	for index, definition := range contract.Definitions {
		scenarioContext.Step(definition.Pattern, functions[index])
	}
}
