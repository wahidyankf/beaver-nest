package policy

import (
	"math"
	"slices"
	"sort"
	"time"
)

const (
	// GiB is one binary gibibyte.
	GiB = int64(1024 * 1024 * 1024)
	// MiB is one binary mebibyte.
	MiB                  = int64(1024 * 1024)
	stateNormal          = "normal"
	stateWarning         = "warning"
	stateCritical        = "critical"
	swapUnavailableState = "unavailable"
	// ReleaseRoutedLatencyP95BudgetMs is the hard routed-user-surface p95 ceiling during release overlap.
	ReleaseRoutedLatencyP95BudgetMs = 500.0
	// ReleaseRoutedLatencyMaxBudgetMs is the hard single routed-user-surface sample ceiling during release overlap.
	ReleaseRoutedLatencyMaxBudgetMs = 2_000.0
)

// Sample is one timestamped host resource observation.
type Sample struct {
	SchemaVersion                       int      `json:"schemaVersion"`
	MeasuredAt                          string   `json:"measuredAt"`
	Platform                            string   `json:"platform,omitempty"`
	Capabilities                        []string `json:"capabilities,omitempty"`
	EffectiveMemoryLimitBytes           int64    `json:"effectiveMemoryLimitBytes,omitempty"`
	AvailableMemoryBytes                *int64   `json:"availableMemoryBytes,omitempty"`
	AvailableNonCompressedEstimateBytes *int64   `json:"availableNonCompressedEstimateBytes"`
	MemoryPressureLevel                 *int     `json:"memoryPressureLevel"`
	CompressorAvailable                 *bool    `json:"compressorAvailable"`
	CompressorPayloadBytes              *int64   `json:"compressorPayloadBytes"`
	PhysicalMemoryBytes                 int64    `json:"physicalMemoryBytes"`
	AvailableParallelism                int      `json:"availableParallelism"`
	CPUUtilizationPercent               *float64 `json:"cpuUtilizationPercent"`
	DiskFreeBytes                       *int64   `json:"diskFreeBytes"`
	DiskTotalBytes                      *int64   `json:"diskTotalBytes,omitempty"`
	PageSizeBytes                       *int64   `json:"pageSizeBytes"`
	CompressorStoredPages               *int64   `json:"compressorStoredPages"`
	CompressorOccupiedPages             *int64   `json:"compressorOccupiedPages"`
	SwapIns                             *int64   `json:"swapIns"`
	SwapOuts                            *int64   `json:"swapOuts"`
	SwapTotalBytes                      *int64   `json:"swapTotalBytes"`
	SwapUsedBytes                       *int64   `json:"swapUsedBytes"`
	SwapFreeBytes                       *int64   `json:"swapFreeBytes"`
	SwapState                           string   `json:"swapState,omitempty"`
	MemoryPSISomeAvg10                  *float64 `json:"memoryPsiSomeAvg10,omitempty"`
	MemoryPSIFullAvg10                  *float64 `json:"memoryPsiFullAvg10,omitempty"`
	OOMEvents                           *int64   `json:"oomEvents,omitempty"`
	OOMKillEvents                       *int64   `json:"oomKillEvents,omitempty"`
}

// CPUState contains cumulative CPU counters used to calculate utilization.
type CPUState []uint64

// Reading combines one sample with the counters needed by the next collection.
type Reading struct {
	CPUState CPUState
	Sample   Sample
}

// Collector produces host readings for admission and monitoring.
type Collector interface {
	Collect(previous CPUState, diskPath string) (Reading, error)
}

// Policy defines thresholds, timing, and resource reservations.
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
	MaxCPUUtilizationPercent       float64
	ConsecutiveCPUSamples          int
	AdmissionWindow                time.Duration
	EphemeralWarningGrace          time.Duration
	ServiceWarningGrace            time.Duration
	TerminationGrace               time.Duration
	LeaseWait                      time.Duration
	SampleInterval                 time.Duration
}

// DevelopmentPolicy is the repository's canonical guarded-development policy.
var DevelopmentPolicy = Policy{
	AdmissionMemoryBytes: 9 * GiB, CriticalMemoryBytes: 4 * GiB,
	DiskWarningBytes: 30 * GiB, DiskCriticalBytes: 20 * GiB,
	TrendWindow:         15 * time.Second,
	SwapOutWarningBytes: 128 * MiB, SwapOutCriticalBytes: 512 * MiB,
	CompressorWarningPayloadBytes: 12 * GiB, CompressorWarningGrowthBytes: 1 * GiB,
	CompressorCriticalPayloadBytes: 16 * GiB, CompressorCriticalGrowthBytes: 2 * GiB,
	ReservedCPUUnits: 2, MaxCPUUtilizationPercent: 85, ConsecutiveCPUSamples: 3,
	AdmissionWindow: 15 * time.Second, EphemeralWarningGrace: 10 * time.Second,
	ServiceWarningGrace: 30 * time.Second, TerminationGrace: 10 * time.Second,
	LeaseWait: 5 * time.Minute, SampleInterval: time.Second,
}

// Assessment classifies current and trend-based resource evidence.
type Assessment struct {
	CompressorGrowthWindowBytes float64 `json:"compressorGrowthWindowBytes"`
	SwapOutWindowBytes          float64 `json:"swapOutWindowBytes"`
	Reason                      string  `json:"reason"`
	State                       string  `json:"state"`
	StorageBlocked              bool    `json:"storageBlocked"`
	SwapState                   string  `json:"swapState,omitempty"`
}

func ptrFinite[T ~int | ~int64](value *T) bool {
	return value != nil
}

// EssentialReadingsValid reports whether required admission evidence is usable.
func EssentialReadingsValid(sample Sample) bool {
	_, timeError := time.Parse(time.RFC3339Nano, sample.MeasuredAt)
	return ptrFinite(availableMemory(sample)) && timeError == nil && sample.DiskFreeBytes != nil && sample.AvailableParallelism > 0
}

func availableMemory(sample Sample) *int64 {
	if sample.AvailableMemoryBytes != nil {
		return sample.AvailableMemoryBytes
	}
	return sample.AvailableNonCompressedEstimateBytes
}

func hasCapability(sample Sample, expected string) bool {
	return slices.Contains(sample.Capabilities, expected)
}

// MemoryState classifies memory evidence as normal, warning, or critical.
func MemoryState(sample Sample, policy Policy) string {
	if !EssentialReadingsValid(sample) {
		return stateCritical
	}
	available := availableMemory(sample)
	criticalPressure := sample.MemoryPressureLevel != nil && *sample.MemoryPressureLevel == 4
	compressorFailed := sample.CompressorAvailable != nil && !*sample.CompressorAvailable && (sample.Platform == "" || hasCapability(sample, "compressor"))
	psiCritical := sample.MemoryPSISomeAvg10 != nil && *sample.MemoryPSISomeAvg10 >= 25 || sample.MemoryPSIFullAvg10 != nil && *sample.MemoryPSIFullAvg10 >= 5
	if criticalPressure || compressorFailed || psiCritical || *available < policy.CriticalMemoryBytes {
		return stateCritical
	}
	warningPressure := sample.MemoryPressureLevel != nil && *sample.MemoryPressureLevel == 2
	psiWarning := sample.MemoryPSISomeAvg10 != nil && *sample.MemoryPSISomeAvg10 >= 10
	if warningPressure || psiWarning || *available < policy.AdmissionMemoryBytes {
		return stateWarning
	}
	return stateNormal
}

// CPUAdmissionReady reports whether utilization preserves reserved execution units.
func CPUAdmissionReady(sample Sample, policy Policy) bool {
	if sample.CPUUtilizationPercent == nil || math.IsNaN(*sample.CPUUtilizationPercent) || math.IsInf(*sample.CPUUtilizationPercent, 0) || sample.AvailableParallelism <= 0 {
		return false
	}
	ceiling := policy.MaxCPUUtilizationPercent
	if ceiling <= 0 {
		reserved := min(policy.ReservedCPUUnits, sample.AvailableParallelism)
		ceiling = 100 * (1 - float64(reserved)/float64(sample.AvailableParallelism))
	}
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

// ResourceAssessment classifies the newest sample and bounded pressure trends.
func ResourceAssessment(samples []Sample, policy Policy) Assessment { //nolint:cyclop // Ordered independent resource signals must remain visibly auditable.
	if len(samples) == 0 {
		return Assessment{Reason: "missing-sample", State: stateCritical}
	}
	current := samples[len(samples)-1]
	pageSize := int64(0)
	if current.PageSizeBytes != nil {
		pageSize = *current.PageSizeBytes
	}
	result := Assessment{
		CompressorGrowthWindowBytes: scaledWindowDelta(samples, func(s Sample) *int64 { return s.CompressorPayloadBytes }, 1, policy),
		SwapOutWindowBytes:          scaledWindowDelta(samples, func(s Sample) *int64 { return s.SwapOuts }, pageSize, policy),
		Reason:                      stateNormal, State: stateNormal, SwapState: current.SwapState,
	}
	if current.DiskFreeBytes == nil {
		result.Reason, result.State, result.StorageBlocked = "disk-unavailable", stateCritical, true
		return result
	}
	result.StorageBlocked = *current.DiskFreeBytes < policy.DiskWarningBytes
	type candidate struct{ reason, state string }
	candidates := []candidate{}
	if len(samples) > 1 {
		previous := samples[len(samples)-2]
		oomIncreased := current.OOMEvents != nil && previous.OOMEvents != nil && *current.OOMEvents > *previous.OOMEvents
		oomKillIncreased := current.OOMKillEvents != nil && previous.OOMKillEvents != nil && *current.OOMKillEvents > *previous.OOMKillEvents
		if oomIncreased || oomKillIncreased {
			candidates = append(candidates, candidate{"memory-oom", stateCritical})
		}
	}
	if *current.DiskFreeBytes < policy.DiskCriticalBytes {
		candidates = append(candidates, candidate{"disk-critical", stateCritical})
	} else if result.StorageBlocked {
		candidates = append(candidates, candidate{"disk-warning", stateWarning})
	}
	if state := MemoryState(current, policy); state != stateNormal {
		reason := "memory-" + state
		if current.MemoryPSISomeAvg10 != nil && *current.MemoryPSISomeAvg10 >= 10 || current.MemoryPSIFullAvg10 != nil && *current.MemoryPSIFullAvg10 >= 5 {
			reason = "memory-psi"
		}
		candidates = append(candidates, candidate{reason, state})
	}
	if current.SwapState != swapUnavailableState && result.SwapOutWindowBytes >= float64(policy.SwapOutCriticalBytes) {
		result.SwapState = "stressed"
		candidates = append(candidates, candidate{"swap-critical", stateCritical})
	} else if current.SwapState != swapUnavailableState && result.SwapOutWindowBytes >= float64(policy.SwapOutWarningBytes) {
		result.SwapState = "stressed"
		candidates = append(candidates, candidate{"swap-warning", stateWarning})
	}
	if current.CompressorPayloadBytes != nil && *current.CompressorPayloadBytes >= policy.CompressorCriticalPayloadBytes && result.CompressorGrowthWindowBytes >= float64(policy.CompressorCriticalGrowthBytes) {
		candidates = append(candidates, candidate{"compressor-critical", stateCritical})
	} else if current.CompressorPayloadBytes != nil && *current.CompressorPayloadBytes >= policy.CompressorWarningPayloadBytes && result.CompressorGrowthWindowBytes >= float64(policy.CompressorWarningGrowthBytes) {
		candidates = append(candidates, candidate{"compressor-warning", stateWarning})
	}
	severity := map[string]int{stateNormal: 0, stateWarning: 1, stateCritical: 2}
	sort.SliceStable(candidates, func(i, j int) bool { return severity[candidates[i].state] > severity[candidates[j].state] })
	if len(candidates) > 0 {
		result.Reason, result.State = candidates[0].reason, candidates[0].state
	}
	return result
}

// AdmissionReady requires a normal assessment and consecutive safe CPU samples.
func AdmissionReady(samples []Sample, policy Policy) bool {
	if ResourceAssessment(samples, policy).State != stateNormal || len(samples) < policy.ConsecutiveCPUSamples {
		return false
	}
	for _, sample := range samples[len(samples)-policy.ConsecutiveCPUSamples:] {
		if !CPUAdmissionReady(sample, policy) {
			return false
		}
	}
	return true
}

// Percentile returns the nearest-rank finite percentile, or nil for no finite values.
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

// ReleaseSummary contains aggregate release-monitor evidence.
type ReleaseSummary struct {
	SchemaVersion                          int      `json:"schemaVersion"`
	Platform                               string   `json:"platform,omitempty"`
	Capabilities                           []string `json:"capabilities,omitempty"`
	SampleCount                            int      `json:"sampleCount"`
	AvailableParallelism                   int      `json:"availableParallelism"`
	AvailableNonCompressedEstimateMinBytes int64    `json:"availableNonCompressedEstimateMinBytes"`
	MemoryPressureLevelMax                 int      `json:"memoryPressureLevelMax"`
	CompressorAvailableAll                 bool     `json:"compressorAvailableAll"`
	CompressorPayloadPeakBytes             int64    `json:"compressorPayloadPeakBytes"`
	PhysicalMemoryBytes                    int64    `json:"physicalMemoryBytes,omitempty"`
	CPUUtilizationP95Percent               float64  `json:"cpuUtilizationP95Percent"`
	ServiceRSSPeakBytes                    int64    `json:"serviceRssPeakBytes,omitempty"`
	DiskFreeMinBytes                       int64    `json:"diskFreeMinBytes"`
	SwapInsDelta                           int64    `json:"swapInsDelta"`
	SwapOutsDelta                          int64    `json:"swapOutsDelta"`
	SwapFreeMinBytes                       int64    `json:"swapFreeMinBytes"`
	CaddyHealthLatencyP95Ms                float64  `json:"caddyHealthLatencyP95Ms,omitempty"`
	HealthFailures                         int      `json:"healthFailures"`
	RoutedJourneyLatencyP95Ms              float64  `json:"routedJourneyLatencyP95Ms,omitempty"`
	RoutedJourneyLatencyMaxMs              float64  `json:"routedJourneyLatencyMaxMs,omitempty"`
	RoutedJourneyFailures                  int      `json:"routedJourneyFailures,omitempty"`
}

// ReleaseHeadroomAvailable validates aggregate capacity for release overlap.
func ReleaseHeadroomAvailable(summary ReleaseSummary) bool {
	swapPressure := (summary.SwapInsDelta > 0 || summary.SwapOutsDelta > 0) && summary.AvailableNonCompressedEstimateMinBytes < 4*GiB
	if summary.AvailableParallelism <= 0 {
		return false
	}
	ceiling := 100 * (1 - 2/float64(summary.AvailableParallelism))
	compressorHealthy := summary.Platform != "darwin" && summary.Platform != "" || summary.CompressorAvailableAll
	routedHealthy := summary.SchemaVersion < 4 ||
		summary.RoutedJourneyFailures == 0 &&
			summary.RoutedJourneyLatencyP95Ms > 0 &&
			summary.RoutedJourneyLatencyP95Ms <= ReleaseRoutedLatencyP95BudgetMs &&
			summary.RoutedJourneyLatencyMaxMs > 0 &&
			summary.RoutedJourneyLatencyMaxMs <= ReleaseRoutedLatencyMaxBudgetMs
	return summary.SampleCount > 0 && summary.AvailableNonCompressedEstimateMinBytes >= 2*GiB && summary.MemoryPressureLevelMax == 1 && compressorHealthy && !swapPressure && summary.CPUUtilizationP95Percent <= ceiling && summary.HealthFailures == 0 && routedHealthy
}

// ReleaseMemoryAvailable reports whether one sample preserves release memory headroom.
func ReleaseMemoryAvailable(sample Sample) bool {
	available := availableMemory(sample)
	compressorHealthy := sample.Platform != "darwin" || sample.CompressorAvailable != nil && *sample.CompressorAvailable
	return available != nil && *available >= 9*GiB && sample.MemoryPressureLevel != nil && *sample.MemoryPressureLevel == 1 && compressorHealthy
}
