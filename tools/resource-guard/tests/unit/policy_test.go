package unit_test

import (
	"math"
	"testing"
	"time"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/guard"
)

func policySample(at time.Time) guard.Sample {
	return guard.Sample{SchemaVersion: 2, MeasuredAt: at.UTC().Format(time.RFC3339Nano), AvailableNonCompressedEstimateBytes: new(12 * guard.GiB), MemoryPressureLevel: new(1), CompressorAvailable: new(true), CompressorPayloadBytes: new(7 * guard.GiB), AvailableParallelism: 12, CPUUtilizationPercent: new(20.0), DiskFreeBytes: new(40 * guard.GiB), PageSizeBytes: new(int64(16_384)), SwapOuts: new(int64(0))}
}

func TestEssentialReadingsAndMemoryStates(t *testing.T) {
	healthy := policySample(time.Unix(0, 0))
	if !guard.EssentialReadingsValid(healthy) || guard.MemoryState(healthy, guard.DevelopmentPolicy) != "normal" {
		t.Fatal("healthy sample rejected")
	}
	invalid := healthy
	invalid.AvailableNonCompressedEstimateBytes = nil
	if guard.EssentialReadingsValid(invalid) || guard.MemoryState(invalid, guard.DevelopmentPolicy) != "critical" {
		t.Fatal("invalid sample accepted")
	}
	critical := healthy
	critical.MemoryPressureLevel = new(4)
	if guard.MemoryState(critical, guard.DevelopmentPolicy) != "critical" {
		t.Fatal("critical pressure ignored")
	}
	compressor := healthy
	compressor.CompressorAvailable = new(false)
	if guard.MemoryState(compressor, guard.DevelopmentPolicy) != "critical" {
		t.Fatal("compressor failure ignored")
	}
	low := healthy
	low.AvailableNonCompressedEstimateBytes = new(3 * guard.GiB)
	if guard.MemoryState(low, guard.DevelopmentPolicy) != "critical" {
		t.Fatal("critical memory ignored")
	}
	warning := healthy
	warning.MemoryPressureLevel = new(2)
	if guard.MemoryState(warning, guard.DevelopmentPolicy) != "warning" {
		t.Fatal("warning pressure ignored")
	}
	warning = healthy
	warning.AvailableNonCompressedEstimateBytes = new(8 * guard.GiB)
	if guard.MemoryState(warning, guard.DevelopmentPolicy) != "warning" {
		t.Fatal("warning memory ignored")
	}
}

func TestCPUAdmissionBoundaries(t *testing.T) {
	sample := policySample(time.Unix(0, 0))
	sample.CPUUtilizationPercent = new(100 * (1 - 2.0/12))
	if !guard.CPUAdmissionReady(sample, guard.DevelopmentPolicy) {
		t.Fatal("ceiling should be inclusive")
	}
	for _, value := range []*float64{nil, new(math.NaN()), new(math.Inf(1))} {
		sample.CPUUtilizationPercent = value
		if guard.CPUAdmissionReady(sample, guard.DevelopmentPolicy) {
			t.Fatal("invalid CPU accepted")
		}
	}
	sample.CPUUtilizationPercent = new(0.0)
	sample.AvailableParallelism = 0
	if guard.CPUAdmissionReady(sample, guard.DevelopmentPolicy) {
		t.Fatal("zero parallelism accepted")
	}
	sample.AvailableParallelism = 1
	if !guard.CPUAdmissionReady(sample, guard.DevelopmentPolicy) {
		t.Fatal("reserved CPU clamp failed")
	}
}

func TestResourceAssessmentBranches(t *testing.T) {
	policy := guard.DevelopmentPolicy
	base := time.Unix(0, 0)
	if got := guard.ResourceAssessment(nil, policy); got.Reason != "missing-sample" || got.State != "critical" {
		t.Fatalf("unexpected empty assessment %+v", got)
	}
	missingDisk := policySample(base)
	missingDisk.DiskFreeBytes = nil
	if got := guard.ResourceAssessment([]guard.Sample{missingDisk}, policy); !got.StorageBlocked || got.Reason != "disk-unavailable" {
		t.Fatalf("unexpected missing disk %+v", got)
	}
	diskCritical := policySample(base)
	diskCritical.DiskFreeBytes = new(19 * guard.GiB)
	diskCritical.MemoryPressureLevel = new(2)
	if got := guard.ResourceAssessment([]guard.Sample{diskCritical}, policy); got.Reason != "disk-critical" || got.State != "critical" {
		t.Fatalf("unexpected critical disk %+v", got)
	}
	memoryWarning := policySample(base)
	memoryWarning.MemoryPressureLevel = new(2)
	if got := guard.ResourceAssessment([]guard.Sample{memoryWarning}, policy); got.Reason != "memory-warning" {
		t.Fatalf("unexpected memory warning %+v", got)
	}
	first, second := policySample(base), policySample(base.Add(15*time.Second))
	second.SwapOuts = new(512 * guard.MiB / 16_384)
	if got := guard.ResourceAssessment([]guard.Sample{first, second}, policy); got.Reason != "swap-critical" {
		t.Fatalf("unexpected swap critical %+v", got)
	}
	first, second = policySample(base), policySample(base.Add(15*time.Second))
	first.CompressorPayloadBytes = new(14 * guard.GiB)
	second.CompressorPayloadBytes = new(16 * guard.GiB)
	if got := guard.ResourceAssessment([]guard.Sample{first, second}, policy); got.Reason != "compressor-critical" {
		t.Fatalf("unexpected compressor critical %+v", got)
	}
	invalidCurrent := policySample(base)
	invalidCurrent.MeasuredAt = "invalid"
	_ = guard.ResourceAssessment([]guard.Sample{invalidCurrent}, policy)
	missingValue := policySample(base)
	missingValue.SwapOuts = nil
	_ = guard.ResourceAssessment([]guard.Sample{missingValue}, policy)
	current := policySample(base.Add(2 * time.Second))
	invalidStart := policySample(base)
	invalidStart.MeasuredAt = "invalid"
	nilStart := policySample(base)
	nilStart.SwapOuts = nil
	future := policySample(base.Add(3 * time.Second))
	old := policySample(base.Add(-20 * time.Second))
	_ = guard.ResourceAssessment([]guard.Sample{invalidStart, nilStart, future, old, current}, policy)
	decreasing := policySample(base.Add(time.Second))
	decreasing.SwapOuts = new(int64(0))
	increasedStart := policySample(base)
	increasedStart.SwapOuts = new(int64(10))
	_ = guard.ResourceAssessment([]guard.Sample{increasedStart, decreasing}, policy)
}

func TestAdmissionPercentileAndReleasePolicies(t *testing.T) {
	base := time.Unix(0, 0)
	samples := []guard.Sample{policySample(base), policySample(base.Add(time.Second)), policySample(base.Add(2 * time.Second))}
	if !guard.AdmissionReady(samples, guard.DevelopmentPolicy) {
		t.Fatal("healthy tail rejected")
	}
	samples[2].CPUUtilizationPercent = new(100.0)
	if guard.AdmissionReady(samples, guard.DevelopmentPolicy) {
		t.Fatal("busy tail accepted")
	}
	if guard.Percentile([]float64{math.NaN(), math.Inf(1)}, .95) != nil {
		t.Fatal("invalid percentile should be nil")
	}
	if got := guard.Percentile([]float64{3, 1, 2, math.NaN()}, .5); got == nil || *got != 2 {
		t.Fatalf("unexpected percentile %v", got)
	}
	healthy := guard.ReleaseSummary{SchemaVersion: 2, SampleCount: 3, AvailableParallelism: 12, AvailableNonCompressedEstimateMinBytes: 13 * guard.GiB, MemoryPressureLevelMax: 1, CompressorAvailableAll: true, CPUUtilizationP95Percent: 50}
	if !guard.ReleaseHeadroomAvailable(healthy) {
		t.Fatal("healthy release rejected")
	}
	invalidParallelism := healthy
	invalidParallelism.AvailableParallelism = 0
	if guard.ReleaseHeadroomAvailable(invalidParallelism) {
		t.Fatal("zero parallelism accepted")
	}
	swapPressure := healthy
	swapPressure.AvailableNonCompressedEstimateMinBytes = 3 * guard.GiB
	swapPressure.SwapOutsDelta = 1
	if guard.ReleaseHeadroomAvailable(swapPressure) {
		t.Fatal("swap pressure accepted")
	}
	bad := []guard.ReleaseSummary{healthy, healthy, healthy, healthy, healthy, healthy}
	bad[0].SampleCount = 0
	bad[1].AvailableNonCompressedEstimateMinBytes = guard.GiB
	bad[2].MemoryPressureLevelMax = 2
	bad[3].CompressorAvailableAll = false
	bad[4].CPUUtilizationP95Percent = 100
	bad[5].HealthFailures = 1
	for _, summary := range bad {
		if guard.ReleaseHeadroomAvailable(summary) {
			t.Fatalf("unhealthy release accepted %+v", summary)
		}
	}
	memory := policySample(base)
	if !guard.ReleaseMemoryAvailable(memory) {
		t.Fatal("healthy release memory rejected")
	}
	memory.AvailableNonCompressedEstimateBytes = nil
	if guard.ReleaseMemoryAvailable(memory) {
		t.Fatal("missing release memory accepted")
	}
}
