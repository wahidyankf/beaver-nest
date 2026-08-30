package release

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/guard"
)

// Check requires consecutive CPU samples plus release memory and disk reserves.
func Check(collector guard.Collector, diskPath string, pause func(time.Duration)) error {
	if collector == nil {
		return errors.New("host collector is required")
	}
	if pause == nil {
		pause = time.Sleep
	}
	var previous guard.CPUState
	consecutive := 0
	for attempt := range 31 {
		reading, err := collector.Collect(previous, diskPath)
		if err != nil {
			return err
		}
		previous = reading.CPUState
		if !guard.ReleaseMemoryAvailable(reading.Sample) {
			return errors.New("memory pressure does not leave safe release headroom")
		}
		if reading.Sample.AvailableParallelism < 8 {
			return errors.New("fewer than eight parallel execution units are available")
		}
		if reading.Sample.DiskFreeBytes == nil || *reading.Sample.DiskFreeBytes < 13*guard.GiB {
			return errors.New("less than 13 GiB release disk is available")
		}
		threshold := 100 * float64(reading.Sample.AvailableParallelism-6) / float64(reading.Sample.AvailableParallelism)
		if reading.Sample.CPUUtilizationPercent != nil && *reading.Sample.CPUUtilizationPercent <= threshold {
			consecutive++
		} else {
			consecutive = 0
		}
		if consecutive >= 3 {
			return nil
		}
		if attempt < 30 {
			pause(500 * time.Millisecond)
		}
	}
	return errors.New("CPU use does not leave release and safety headroom")
}

// AssessFile validates one completed release summary.
func AssessFile(path string) (guard.ReleaseSummary, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return guard.ReleaseSummary{}, err
	}
	var summary guard.ReleaseSummary
	if err = json.Unmarshal(data, &summary); err != nil {
		return guard.ReleaseSummary{}, err
	}
	if summary.SchemaVersion != 2 || summary.SampleCount <= 0 || summary.AvailableParallelism <= 0 {
		return summary, errors.New("resource evidence summary is invalid")
	}
	if !guard.ReleaseHeadroomAvailable(summary) {
		return summary, errors.New("release overlap exhausted resource headroom")
	}
	return summary, nil
}

// MonitorConfig describes one bounded release-monitoring session.
type MonitorConfig struct {
	OutputPath, SummaryPath, DeploymentRoot string
	Duration                                time.Duration
	Collector                               guard.Collector
	Interval                                time.Duration
	ServiceRSS                              func() int64
	Health                                  func() (int, float64)
	LoadAverage                             func() float64
}
type releaseSample struct {
	guard.Sample

	OneMinuteLoad        float64 `json:"oneMinuteLoad"`
	ServiceRSSBytes      int64   `json:"serviceRssBytes"`
	CaddyHealthStatus    int     `json:"caddyHealthStatus"`
	CaddyHealthLatencyMs float64 `json:"caddyHealthLatencyMs"`
}

func output(command string, arguments ...string) string {
	value, err := exec.Command(command, arguments...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(value))
}

func serviceRSSBytes() int64 {
	pids := map[string]bool{}
	for _, port := range []int{4000, 4001, 4100} {
		for pid := range strings.FieldsSeq(output("lsof", "-nP", fmt.Sprintf("-iTCP:%d", port), "-sTCP:LISTEN", "-t")) {
			pids[pid] = true
		}
	}
	if len(pids) == 0 {
		return 0
	}
	list := make([]string, 0, len(pids))
	for pid := range pids {
		list = append(list, pid)
	}
	var total int64
	for field := range strings.FieldsSeq(output("ps", "-o", "rss=", "-p", strings.Join(list, ","))) {
		value, _ := strconv.ParseInt(field, 10, 64)
		total += value * 1024
	}
	return total
}

func caddyHealth() (int, float64) {
	value := output("curl", "-sS", "--max-time", "3", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "http://127.0.0.1:4100/health/ready")
	fields := strings.Fields(value)
	if len(fields) != 2 {
		return 0, 3000
	}
	status, _ := strconv.Atoi(fields[0])
	seconds, err := strconv.ParseFloat(fields[1], 64)
	if err != nil {
		return 0, 3000
	}
	return status, seconds * 1000
}

func oneMinuteLoad() float64 {
	fields := strings.Fields(strings.Trim(output("sysctl", "-n", "vm.loadavg"), "{} "))
	if len(fields) == 0 {
		return 0
	}
	value, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0
	}
	return value
}

// RunMonitor records release overlap samples until duration or signal completion.
func RunMonitor(config MonitorConfig) error {
	if config.OutputPath == "" || config.SummaryPath == "" || config.DeploymentRoot == "" {
		return errors.New("output, summary, and deployment root are required")
	}
	if config.Collector == nil {
		return errors.New("host collector is required")
	}
	if config.ServiceRSS == nil {
		config.ServiceRSS = serviceRSSBytes
	}
	if config.Health == nil {
		config.Health = caddyHealth
	}
	if config.LoadAverage == nil {
		config.LoadAverage = oneMinuteLoad
	}
	if config.Interval == 0 {
		config.Interval = time.Second
	}
	if err := guard.CleanupEvidence(filepath.Dir(config.OutputPath), time.Now(), config.OutputPath, config.SummaryPath); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(config.OutputPath), 0o700); err != nil {
		return err
	}
	file, err := os.OpenFile(config.OutputPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()
	written := bufio.NewWriter(file)
	samples := []releaseSample{}
	var previous guard.CPUState
	sample := func() error {
		reading, collectError := config.Collector.Collect(previous, config.DeploymentRoot)
		if collectError != nil {
			return collectError
		}
		previous = reading.CPUState
		status, latency := config.Health()
		value := releaseSample{Sample: reading.Sample, OneMinuteLoad: config.LoadAverage(), ServiceRSSBytes: config.ServiceRSS(), CaddyHealthStatus: status, CaddyHealthLatencyMs: latency}
		samples = append(samples, value)
		encoded, marshalError := json.Marshal(value)
		if marshalError != nil {
			return marshalError
		}
		_, writeError := written.Write(append(encoded, '\n'))
		if writeError != nil {
			return writeError
		}
		return written.Flush()
	}
	if err := sample(); err != nil {
		return err
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(signals)
	ticker := time.NewTicker(config.Interval)
	defer ticker.Stop()
	var duration <-chan time.Time
	if config.Duration > 0 {
		timer := time.NewTimer(config.Duration)
		defer timer.Stop()
		duration = timer.C
	}
loop:
	for {
		select {
		case <-ticker.C:
			if err := sample(); err != nil {
				return err
			}
		case <-signals:
			break loop
		case <-duration:
			break loop
		}
	}
	return writeSummary(config.SummaryPath, samples)
}

func writeSummary(path string, samples []releaseSample) error {
	if len(samples) == 0 {
		return errors.New("release monitor has no samples")
	}
	summary := guard.ReleaseSummary{SchemaVersion: 2, SampleCount: len(samples), AvailableParallelism: samples[0].AvailableParallelism, CompressorAvailableAll: true, MemoryPressureLevelMax: 0, AvailableNonCompressedEstimateMinBytes: math.MaxInt64, DiskFreeMinBytes: math.MaxInt64, SwapFreeMinBytes: math.MaxInt64}
	cpu, latency := []float64{}, []float64{}
	first, last := samples[0], samples[len(samples)-1]
	for _, sample := range samples {
		if sample.AvailableNonCompressedEstimateBytes != nil {
			summary.AvailableNonCompressedEstimateMinBytes = min(summary.AvailableNonCompressedEstimateMinBytes, *sample.AvailableNonCompressedEstimateBytes)
		}
		if sample.MemoryPressureLevel != nil {
			summary.MemoryPressureLevelMax = max(summary.MemoryPressureLevelMax, *sample.MemoryPressureLevel)
		}
		if sample.CompressorAvailable == nil || !*sample.CompressorAvailable {
			summary.CompressorAvailableAll = false
		}
		if sample.CompressorPayloadBytes != nil {
			summary.CompressorPayloadPeakBytes = max(summary.CompressorPayloadPeakBytes, *sample.CompressorPayloadBytes)
		}
		if sample.CPUUtilizationPercent != nil {
			cpu = append(cpu, *sample.CPUUtilizationPercent)
		}
		if sample.DiskFreeBytes != nil {
			summary.DiskFreeMinBytes = min(summary.DiskFreeMinBytes, *sample.DiskFreeBytes)
		}
		if sample.SwapFreeBytes != nil {
			summary.SwapFreeMinBytes = min(summary.SwapFreeMinBytes, *sample.SwapFreeBytes)
		}
		summary.ServiceRSSPeakBytes = max(summary.ServiceRSSPeakBytes, sample.ServiceRSSBytes)
		latency = append(latency, sample.CaddyHealthLatencyMs)
		if sample.CaddyHealthStatus != 200 {
			summary.HealthFailures++
		}
	}
	summary.PhysicalMemoryBytes = first.PhysicalMemoryBytes
	if first.SwapIns != nil && last.SwapIns != nil {
		summary.SwapInsDelta = max(0, *last.SwapIns-*first.SwapIns)
	}
	if first.SwapOuts != nil && last.SwapOuts != nil {
		summary.SwapOutsDelta = max(0, *last.SwapOuts-*first.SwapOuts)
	}
	if value := guard.Percentile(cpu, .95); value != nil {
		summary.CPUUtilizationP95Percent = *value
	}
	if value := guard.Percentile(latency, .95); value != nil {
		summary.CaddyHealthLatencyP95Ms = *value
	}
	encoded, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()
	_, err = file.Write(append(encoded, '\n'))
	return err
}
