package integration_test

import (
	"bytes"
	"os"
	"testing"
	"time"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/guard"
)

type integrationCollector struct {
	samples []guard.Sample
	index   int
}

func (collector *integrationCollector) Collect(previous guard.CPUState, _ string) (guard.Reading, error) {
	index := min(collector.index, len(collector.samples)-1)
	collector.index++
	return guard.Reading{CPUState: previous, Sample: collector.samples[index]}, nil
}

func integrationSample(at time.Time) guard.Sample {
	available, payload, disk, page, swaps := 12*guard.GiB, 7*guard.GiB, 40*guard.GiB, int64(16_384), int64(0)
	level, compressor, cpu := 1, true, 10.0
	return guard.Sample{SchemaVersion: 2, MeasuredAt: at.UTC().Format(time.RFC3339Nano), AvailableNonCompressedEstimateBytes: &available, MemoryPressureLevel: &level, CompressorAvailable: &compressor, CompressorPayloadBytes: &payload, AvailableParallelism: 12, CPUUtilizationPercent: &cpu, DiskFreeBytes: &disk, PageSizeBytes: &page, SwapOuts: &swaps}
}

func fastPolicy() guard.Policy {
	policy := guard.DevelopmentPolicy
	policy.SampleInterval = time.Millisecond
	policy.AdmissionWindow = time.Second
	policy.TerminationGrace = time.Millisecond
	policy.LeaseWait = time.Second
	return policy
}

func TestGuardPreservesChildExitAndWritesEvidence(t *testing.T) {
	base := time.Now()
	collector := &integrationCollector{samples: []guard.Sample{integrationSample(base), integrationSample(base.Add(time.Millisecond)), integrationSample(base.Add(2 * time.Millisecond))}}
	code, err := guard.Run(guard.RunConfig{Command: "/bin/sh", Arguments: []string{"-c", "exit 17"}, TaskClass: "ephemeral", EvidenceRoot: t.TempDir(), DiskPath: ".", Collector: collector, Policy: fastPolicy(), Sleep: func(time.Duration) {}, Now: time.Now, Stderr: &bytes.Buffer{}, Environment: os.Environ()})
	if err != nil || code != 17 {
		t.Fatalf("exit=%d error=%v", code, err)
	}
}

func TestGuardReturnsStorageCodeBeforeStartingChild(t *testing.T) {
	sample := integrationSample(time.Now())
	disk := 29 * guard.GiB
	sample.DiskFreeBytes = &disk
	code, err := guard.Run(guard.RunConfig{Command: "/bin/sh", Arguments: []string{"-c", "exit 99"}, TaskClass: "ephemeral", EvidenceRoot: t.TempDir(), DiskPath: ".", Collector: &integrationCollector{samples: []guard.Sample{sample}}, Policy: fastPolicy(), Sleep: func(time.Duration) {}, Now: time.Now, Stderr: &bytes.Buffer{}, Environment: os.Environ()})
	if err != nil || code != guard.StorageBlockedExitCode {
		t.Fatalf("exit=%d error=%v", code, err)
	}
}

func TestInheritedGuardRunsDirectlyAndKeepsPortLease(t *testing.T) {
	root, portRoot := t.TempDir(), t.TempDir()
	session, err := guard.AcquireSession(root, "", "ephemeral", time.Second, func(time.Duration) {})
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = guard.ReleaseSession(root, session) }()
	code, err := guard.Run(guard.RunConfig{Command: "/bin/sh", Arguments: []string{"-c", "exit 0"}, TaskClass: "ephemeral", EvidenceRoot: root, DiskPath: ".", Collector: &integrationCollector{samples: []guard.Sample{integrationSample(time.Now())}}, Policy: fastPolicy(), Sleep: func(time.Duration) {}, Now: time.Now, Stderr: &bytes.Buffer{}, Environment: []string{"BNEST_RESOURCE_SESSION=" + session.Token}, LeasePort: 45_123, LeaseOwner: "integration", LeaseMinimum: 45_000, LeaseMaximum: 46_000, PortLeaseRoot: portRoot})
	if err != nil || code != 0 {
		t.Fatalf("exit=%d error=%v", code, err)
	}
}

func TestGuardShedsCriticalEphemeralChild(t *testing.T) {
	base := time.Now()
	healthy := integrationSample(base)
	critical := integrationSample(base.Add(3 * time.Millisecond))
	level := 4
	critical.MemoryPressureLevel = &level
	collector := &integrationCollector{samples: []guard.Sample{healthy, healthy, healthy, critical}}
	code, err := guard.Run(guard.RunConfig{Command: "/bin/sh", Arguments: []string{"-c", "sleep 5"}, TaskClass: "ephemeral", EvidenceRoot: t.TempDir(), DiskPath: ".", Collector: collector, Policy: fastPolicy(), Sleep: func(time.Duration) {}, Now: time.Now, Stderr: &bytes.Buffer{}, Environment: os.Environ()})
	if err != nil || code != guard.CapacityDeferredExitCode {
		t.Fatalf("exit=%d error=%v", code, err)
	}
}

func TestGuardInjectsResolvedConcurrencyWithoutOverwritingCaller(t *testing.T) {
	base := time.Now()
	collector := &integrationCollector{samples: []guard.Sample{integrationSample(base), integrationSample(base.Add(time.Millisecond)), integrationSample(base.Add(2 * time.Millisecond))}}
	resolution := guard.Resolution{RequestedProfile: "balanced", ResolvedProfile: "minimal", FallbackChain: []string{"balanced", "constrained", "minimal"}, Concurrency: 1}
	command := `[ "$RESOURCE_GUARD_PROFILE" = minimal ] && [ "$RESOURCE_GUARD_CONCURRENCY" = 1 ] && [ "$NX_PARALLEL" = 7 ] && [ "$GOMAXPROCS" = 6 ] && [ "$DOTNET_PROCESSOR_COUNT" = 5 ]`
	environment := []string{"PATH=" + os.Getenv("PATH"), "NX_PARALLEL=7", "GOMAXPROCS=6", "DOTNET_PROCESSOR_COUNT=5"}
	code, err := guard.Run(guard.RunConfig{Command: "/bin/sh", Arguments: []string{"-c", command}, TaskClass: "ephemeral", EvidenceRoot: t.TempDir(), DiskPath: ".", Collector: collector, Policy: fastPolicy(), Resolution: resolution, Sleep: func(time.Duration) {}, Now: time.Now, Stderr: &bytes.Buffer{}, Environment: environment})
	if err != nil || code != 0 {
		t.Fatalf("exit=%d error=%v", code, err)
	}
}
