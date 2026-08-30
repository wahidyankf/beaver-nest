package release

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/guard"
)

// Check requires consecutive CPU samples plus release memory and disk reserves.
func Check(collector guard.Collector, diskPath string, pause func(time.Duration)) error {
	return CheckWithPolicy(collector, diskPath, pause, guard.DevelopmentPolicy)
}

// CheckWithPolicy requires consecutive samples inside one resolved strict profile.
func CheckWithPolicy(collector guard.Collector, diskPath string, pause func(time.Duration), policy guard.Policy) error {
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
		if guard.MemoryState(reading.Sample, policy) != "normal" {
			return errors.New("memory pressure does not leave safe release headroom")
		}
		if reading.Sample.DiskFreeBytes == nil || *reading.Sample.DiskFreeBytes < policy.DiskWarningBytes {
			return errors.New("release disk reserve is unavailable")
		}
		if guard.CPUAdmissionReady(reading.Sample, policy) {
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
	if summary.SchemaVersion != 2 && summary.SchemaVersion != 3 && summary.SchemaVersion != 4 || summary.SampleCount <= 0 || summary.AvailableParallelism <= 0 {
		return summary, errors.New("resource evidence summary is invalid")
	}
	if !guard.ReleaseHeadroomAvailable(summary) {
		return summary, errors.New("release overlap exhausted resource or routed responsiveness headroom")
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
	RoutedHealth                            func() (int, float64)
	RoutedOrigin                            string
	LoadAverage                             func() float64
}
type releaseSample struct {
	guard.Sample

	OneMinuteLoad          float64 `json:"oneMinuteLoad"`
	ServiceRSSBytes        int64   `json:"serviceRssBytes"`
	CaddyHealthStatus      int     `json:"caddyHealthStatus"`
	CaddyHealthLatencyMs   float64 `json:"caddyHealthLatencyMs"`
	RoutedJourneyStatus    int     `json:"routedJourneyStatus"`
	RoutedJourneyLatencyMs float64 `json:"routedJourneyLatencyMs"`
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

func probeHTTP(target string) (int, float64) {
	value := output("curl", "-sS", "--max-time", "3", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", target)
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

func caddyHealth() (int, float64) {
	return probeHTTP("http://127.0.0.1:4100/health/ready")
}

func routedHealth(origin string) (func() (int, float64), error) {
	parsed, err := url.Parse(origin)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || parsed.Path != "" && parsed.Path != "/" {
		return nil, errors.New("bare HTTPS routed origin is required for release monitoring")
	}
	target := strings.TrimSuffix(origin, "/") + "/"
	return func() (int, float64) { return probeHTTP(target) }, nil
}

func oneMinuteLoad() float64 {
	if data, err := os.ReadFile("/proc/loadavg"); err == nil {
		fields := strings.Fields(string(data))
		if len(fields) > 0 {
			if value, parseError := strconv.ParseFloat(fields[0], 64); parseError == nil {
				return value
			}
		}
	}
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
	if config.RoutedHealth == nil {
		probe, probeError := routedHealth(config.RoutedOrigin)
		if probeError != nil {
			return probeError
		}
		config.RoutedHealth = probe
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
		routedStatus, routedLatency := config.RoutedHealth()
		value := releaseSample{Sample: reading.Sample, OneMinuteLoad: config.LoadAverage(), ServiceRSSBytes: config.ServiceRSS(), CaddyHealthStatus: status, CaddyHealthLatencyMs: latency, RoutedJourneyStatus: routedStatus, RoutedJourneyLatencyMs: routedLatency}
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

func recordRoutedEvidence(summary *guard.ReleaseSummary, latencies *[]float64, sample releaseSample) {
	*latencies = append(*latencies, sample.RoutedJourneyLatencyMs)
	summary.RoutedJourneyLatencyMaxMs = max(summary.RoutedJourneyLatencyMaxMs, sample.RoutedJourneyLatencyMs)
	if sample.RoutedJourneyStatus != 200 {
		summary.RoutedJourneyFailures++
	}
}

func writeSummary(path string, samples []releaseSample) error {
	if len(samples) == 0 {
		return errors.New("release monitor has no samples")
	}
	summary := guard.ReleaseSummary{SchemaVersion: 4, Platform: samples[0].Platform, Capabilities: append([]string(nil), samples[0].Capabilities...), SampleCount: len(samples), AvailableParallelism: samples[0].AvailableParallelism, CompressorAvailableAll: true, MemoryPressureLevelMax: 0, AvailableNonCompressedEstimateMinBytes: math.MaxInt64, DiskFreeMinBytes: math.MaxInt64, SwapFreeMinBytes: math.MaxInt64}
	cpu, latency, routedLatency := []float64{}, []float64{}, []float64{}
	first, last := samples[0], samples[len(samples)-1]
	for _, sample := range samples {
		available := sample.AvailableMemoryBytes
		if available == nil {
			available = sample.AvailableNonCompressedEstimateBytes
		}
		if available != nil {
			summary.AvailableNonCompressedEstimateMinBytes = min(summary.AvailableNonCompressedEstimateMinBytes, *available)
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
		recordRoutedEvidence(&summary, &routedLatency, sample)
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
	if value := guard.Percentile(routedLatency, .95); value != nil {
		summary.RoutedJourneyLatencyP95Ms = *value
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
