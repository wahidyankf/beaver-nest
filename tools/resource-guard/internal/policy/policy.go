package policy

import (
	"math"
	"sort"
	"time"
)

const (
	GiB = int64(1024 * 1024 * 1024)
	MiB = int64(1024 * 1024)
)

type Sample struct {
	SchemaVersion                       int      `json:"schemaVersion"`
	MeasuredAt                          string   `json:"measuredAt"`
	AvailableNonCompressedEstimateBytes *int64   `json:"availableNonCompressedEstimateBytes"`
	MemoryPressureLevel                 *int     `json:"memoryPressureLevel"`
	CompressorAvailable                 *bool    `json:"compressorAvailable"`
	CompressorPayloadBytes              *int64   `json:"compressorPayloadBytes"`
	PhysicalMemoryBytes                 int64    `json:"physicalMemoryBytes"`
	AvailableParallelism                int      `json:"availableParallelism"`
	CPUUtilizationPercent               *float64 `json:"cpuUtilizationPercent"`
	DiskFreeBytes                       *int64   `json:"diskFreeBytes"`
	PageSizeBytes                       *int64   `json:"pageSizeBytes"`
	CompressorStoredPages               *int64   `json:"compressorStoredPages"`
	CompressorOccupiedPages             *int64   `json:"compressorOccupiedPages"`
	SwapIns                             *int64   `json:"swapIns"`
	SwapOuts                            *int64   `json:"swapOuts"`
	SwapTotalBytes                      *int64   `json:"swapTotalBytes"`
	SwapUsedBytes                       *int64   `json:"swapUsedBytes"`
	SwapFreeBytes                       *int64   `json:"swapFreeBytes"`
}

type CPUState []uint64

type Reading struct {
	CPUState CPUState
	Sample   Sample
}

type Collector interface {
	Collect(previous CPUState, diskPath string) (Reading, error)
}

type Policy struct {
	AdmissionMemoryBytes           int64
	CriticalMemoryBytes            int64
	DiskWarningBytes               int64
	DiskCriticalBytes              int64
	TrendWindow                    time.Duration
	SwapOutWarningBytes            int64
	SwapOutCriticalBytes           int64
	CompressorWarningPayloadBytes  int64
	CompressorWarningGrowthBytes   int64
	CompressorCriticalPayloadBytes int64
	CompressorCriticalGrowthBytes  int64
	ReservedCPUUnits               int
	ConsecutiveCPUSamples          int
	AdmissionWindow                time.Duration
	EphemeralWarningGrace          time.Duration
	ServiceWarningGrace            time.Duration
	TerminationGrace               time.Duration
	LeaseWait                      time.Duration
	SampleInterval                 time.Duration
}

var DevelopmentPolicy = Policy{
	AdmissionMemoryBytes: 9 * GiB, CriticalMemoryBytes: 4 * GiB,
	DiskWarningBytes: 30 * GiB, DiskCriticalBytes: 20 * GiB,
	TrendWindow:         15 * time.Second,
	SwapOutWarningBytes: 128 * MiB, SwapOutCriticalBytes: 512 * MiB,
	CompressorWarningPayloadBytes: 12 * GiB, CompressorWarningGrowthBytes: 1 * GiB,
	CompressorCriticalPayloadBytes: 16 * GiB, CompressorCriticalGrowthBytes: 2 * GiB,
	ReservedCPUUnits: 2, ConsecutiveCPUSamples: 3,
	AdmissionWindow: 15 * time.Second, EphemeralWarningGrace: 10 * time.Second,
	ServiceWarningGrace: 30 * time.Second, TerminationGrace: 10 * time.Second,
	LeaseWait: 5 * time.Minute, SampleInterval: time.Second,
}

type Assessment struct {
	CompressorGrowthWindowBytes float64 `json:"compressorGrowthWindowBytes"`
	SwapOutWindowBytes          float64 `json:"swapOutWindowBytes"`
	Reason                      string  `json:"reason"`
	State                       string  `json:"state"`
	StorageBlocked              bool    `json:"storageBlocked"`
}

func ptrFinite[T ~int | ~int64](value *T) bool {
	return value != nil
}

func EssentialReadingsValid(sample Sample) bool {
	validLevel := sample.MemoryPressureLevel != nil && (*sample.MemoryPressureLevel == 1 || *sample.MemoryPressureLevel == 2 || *sample.MemoryPressureLevel == 4)
	_, timeError := time.Parse(time.RFC3339Nano, sample.MeasuredAt)
	return ptrFinite(sample.AvailableNonCompressedEstimateBytes) && validLevel && sample.CompressorAvailable != nil &&
		ptrFinite(sample.CompressorPayloadBytes) && timeError == nil && sample.PageSizeBytes != nil && *sample.PageSizeBytes > 0 &&
		ptrFinite(sample.SwapOuts) && sample.AvailableParallelism > 0
}

func MemoryState(sample Sample, policy Policy) string {
	if !EssentialReadingsValid(sample) {
		return "critical"
	}
	if *sample.MemoryPressureLevel == 4 || !*sample.CompressorAvailable || *sample.AvailableNonCompressedEstimateBytes < policy.CriticalMemoryBytes {
		return "critical"
	}
	if *sample.MemoryPressureLevel == 2 || *sample.AvailableNonCompressedEstimateBytes < policy.AdmissionMemoryBytes {
		return "warning"
	}
	return "normal"
}

func CPUAdmissionReady(sample Sample, policy Policy) bool {
	if sample.CPUUtilizationPercent == nil || math.IsNaN(*sample.CPUUtilizationPercent) || math.IsInf(*sample.CPUUtilizationPercent, 0) || sample.AvailableParallelism <= 0 {
		return false
	}
	reserved := min(policy.ReservedCPUUnits, sample.AvailableParallelism)
	ceiling := 100 * (1 - float64(reserved)/float64(sample.AvailableParallelism))
	return *sample.CPUUtilizationPercent <= ceiling
}

func scaledWindowDelta(samples []Sample, value func(Sample) *int64, multiplier int64, policy Policy) float64 {
	current := samples[len(samples)-1]
	currentValue := value(current)
	currentTime, err := time.Parse(time.RFC3339Nano, current.MeasuredAt)
	if err != nil || currentValue == nil {
		return 0
	}
	for _, candidate := range samples[:len(samples)-1] {
		candidateTime, parseError := time.Parse(time.RFC3339Nano, candidate.MeasuredAt)
		candidateValue := value(candidate)
		deltaTime := currentTime.Sub(candidateTime)
		if parseError != nil || candidateValue == nil || deltaTime <= 0 || deltaTime > policy.TrendWindow {
			continue
		}
		delta := *currentValue - *candidateValue
		if delta <= 0 {
			return 0
		}
		return float64(delta*multiplier) * float64(policy.TrendWindow) / float64(deltaTime)
	}
	return 0
}

func ResourceAssessment(samples []Sample, policy Policy) Assessment {
	if len(samples) == 0 {
		return Assessment{Reason: "missing-sample", State: "critical"}
	}
	current := samples[len(samples)-1]
	pageSize := int64(0)
	if current.PageSizeBytes != nil {
		pageSize = *current.PageSizeBytes
	}
	result := Assessment{
		CompressorGrowthWindowBytes: scaledWindowDelta(samples, func(s Sample) *int64 { return s.CompressorPayloadBytes }, 1, policy),
		SwapOutWindowBytes:          scaledWindowDelta(samples, func(s Sample) *int64 { return s.SwapOuts }, pageSize, policy),
		Reason:                      "normal", State: "normal",
	}
	if current.DiskFreeBytes == nil {
		result.Reason, result.State, result.StorageBlocked = "disk-unavailable", "critical", true
		return result
	}
	result.StorageBlocked = *current.DiskFreeBytes < policy.DiskWarningBytes
	type candidate struct{ reason, state string }
	candidates := []candidate{}
	if *current.DiskFreeBytes < policy.DiskCriticalBytes {
		candidates = append(candidates, candidate{"disk-critical", "critical"})
	} else if result.StorageBlocked {
		candidates = append(candidates, candidate{"disk-warning", "warning"})
	}
	if state := MemoryState(current, policy); state != "normal" {
		candidates = append(candidates, candidate{"memory-" + state, state})
	}
	if result.SwapOutWindowBytes >= float64(policy.SwapOutCriticalBytes) {
		candidates = append(candidates, candidate{"swap-critical", "critical"})
	} else if result.SwapOutWindowBytes >= float64(policy.SwapOutWarningBytes) {
		candidates = append(candidates, candidate{"swap-warning", "warning"})
	}
	if current.CompressorPayloadBytes != nil && *current.CompressorPayloadBytes >= policy.CompressorCriticalPayloadBytes && result.CompressorGrowthWindowBytes >= float64(policy.CompressorCriticalGrowthBytes) {
		candidates = append(candidates, candidate{"compressor-critical", "critical"})
	} else if current.CompressorPayloadBytes != nil && *current.CompressorPayloadBytes >= policy.CompressorWarningPayloadBytes && result.CompressorGrowthWindowBytes >= float64(policy.CompressorWarningGrowthBytes) {
		candidates = append(candidates, candidate{"compressor-warning", "warning"})
	}
	severity := map[string]int{"normal": 0, "warning": 1, "critical": 2}
	sort.SliceStable(candidates, func(i, j int) bool { return severity[candidates[i].state] > severity[candidates[j].state] })
	if len(candidates) > 0 {
		result.Reason, result.State = candidates[0].reason, candidates[0].state
	}
	return result
}

func AdmissionReady(samples []Sample, policy Policy) bool {
	if ResourceAssessment(samples, policy).State != "normal" || len(samples) < policy.ConsecutiveCPUSamples {
		return false
	}
	for _, sample := range samples[len(samples)-policy.ConsecutiveCPUSamples:] {
		if !CPUAdmissionReady(sample, policy) {
			return false
		}
	}
	return true
}

func Percentile(values []float64, proportion float64) *float64 {
	finite := make([]float64, 0, len(values))
	for _, value := range values {
		if !math.IsNaN(value) && !math.IsInf(value, 0) {
			finite = append(finite, value)
		}
	}
	if len(finite) == 0 {
		return nil
	}
	sort.Float64s(finite)
	index := max(0, int(math.Ceil(float64(len(finite))*proportion))-1)
	return &finite[index]
}

type ReleaseSummary struct {
	SchemaVersion                          int     `json:"schemaVersion"`
	SampleCount                            int     `json:"sampleCount"`
	AvailableParallelism                   int     `json:"availableParallelism"`
	AvailableNonCompressedEstimateMinBytes int64   `json:"availableNonCompressedEstimateMinBytes"`
	MemoryPressureLevelMax                 int     `json:"memoryPressureLevelMax"`
	CompressorAvailableAll                 bool    `json:"compressorAvailableAll"`
	CompressorPayloadPeakBytes             int64   `json:"compressorPayloadPeakBytes"`
	PhysicalMemoryBytes                    int64   `json:"physicalMemoryBytes,omitempty"`
	CPUUtilizationP95Percent               float64 `json:"cpuUtilizationP95Percent"`
	ServiceRSSPeakBytes                    int64   `json:"serviceRssPeakBytes,omitempty"`
	DiskFreeMinBytes                       int64   `json:"diskFreeMinBytes"`
	SwapInsDelta                           int64   `json:"swapInsDelta"`
	SwapOutsDelta                          int64   `json:"swapOutsDelta"`
	SwapFreeMinBytes                       int64   `json:"swapFreeMinBytes"`
	CaddyHealthLatencyP95Ms                float64 `json:"caddyHealthLatencyP95Ms,omitempty"`
	HealthFailures                         int     `json:"healthFailures"`
}

func ReleaseHeadroomAvailable(summary ReleaseSummary) bool {
	swapPressure := (summary.SwapInsDelta > 0 || summary.SwapOutsDelta > 0) && summary.AvailableNonCompressedEstimateMinBytes < 4*GiB
	if summary.AvailableParallelism <= 0 {
		return false
	}
	ceiling := 100 * (1 - 2/float64(summary.AvailableParallelism))
	return summary.SampleCount > 0 && summary.AvailableNonCompressedEstimateMinBytes >= 2*GiB && summary.MemoryPressureLevelMax == 1 && summary.CompressorAvailableAll && !swapPressure && summary.CPUUtilizationP95Percent <= ceiling && summary.HealthFailures == 0
}

func ReleaseMemoryAvailable(sample Sample) bool {
	return sample.AvailableNonCompressedEstimateBytes != nil && *sample.AvailableNonCompressedEstimateBytes >= 9*GiB && sample.MemoryPressureLevel != nil && *sample.MemoryPressureLevel == 1 && sample.CompressorAvailable != nil && *sample.CompressorAvailable
}
