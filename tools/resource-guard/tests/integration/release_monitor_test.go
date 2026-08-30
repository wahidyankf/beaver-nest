package integration_test

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/guard"
	releaseguard "github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/release"
)

func TestReleaseMonitorWritesAndAssessesPrivateEvidence(t *testing.T) {
	root := t.TempDir()
	outputPath, summaryPath := filepath.Join(root, "samples.jsonl"), filepath.Join(root, "summary.json")
	base := time.Now()
	samples := []guard.Sample{integrationSample(base), integrationSample(base.Add(time.Millisecond)), integrationSample(base.Add(2 * time.Millisecond))}
	for index := range samples {
		swapIn, swapOut, swapFree := int64(index), int64(index), 2*guard.GiB
		samples[index].SwapIns, samples[index].SwapOuts, samples[index].SwapFreeBytes = &swapIn, &swapOut, &swapFree
	}
	err := releaseguard.RunMonitor(releaseguard.MonitorConfig{OutputPath: outputPath, SummaryPath: summaryPath, DeploymentRoot: root, Duration: 3 * time.Millisecond, Interval: time.Millisecond, Collector: &integrationCollector{samples: samples}, ServiceRSS: func() int64 { return 4096 }, Health: func() (int, float64) { return 200, 2.5 }, LoadAverage: func() float64 { return 1.5 }})
	if err != nil {
		t.Fatal(err)
	}
	if info, statError := os.Stat(outputPath); statError != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("invalid output mode: info=%v error=%v", info, statError)
	}
	summary, err := releaseguard.AssessFile(summaryPath)
	if err != nil {
		t.Fatal(err)
	}
	if summary.SchemaVersion != 3 || summary.SampleCount < 2 || summary.ServiceRSSPeakBytes != 4096 || summary.HealthFailures != 0 {
		t.Fatalf("unexpected summary %+v", summary)
	}
}

func TestReleaseAssessmentRejectsInvalidAndUnhealthyEvidence(t *testing.T) {
	root := t.TempDir()
	invalid := filepath.Join(root, "invalid.json")
	if err := os.WriteFile(invalid, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := releaseguard.AssessFile(invalid); err == nil {
		t.Fatal("invalid summary accepted")
	}
	unhealthy := filepath.Join(root, "unhealthy.json")
	data := []byte(`{"schemaVersion":2,"sampleCount":1,"availableParallelism":12,"availableNonCompressedEstimateMinBytes":13958643712,"memoryPressureLevelMax":1,"compressorAvailableAll":true,"cpuUtilizationP95Percent":10,"healthFailures":1}`)
	if err := os.WriteFile(unhealthy, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := releaseguard.AssessFile(unhealthy); err == nil {
		t.Fatal("unhealthy summary accepted")
	}
}
