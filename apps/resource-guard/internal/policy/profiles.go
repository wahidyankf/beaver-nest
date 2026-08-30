package policy

import (
	"errors"
	"fmt"
	"math"
)

const (
	// HardDiskFloorBytes is the immutable cleanup boundary.
	HardDiskFloorBytes = 256 * MiB
	// ReplanRequiredExitCode is used when strict capacity or configuration is incompatible.
	ReplanRequiredExitCode = 78
	profileBalanced        = "balanced"
	profileConstrained     = "constrained"
	profileMinimal         = "minimal"
	swapUnavailable        = "unavailable"
)

// Profile defines one adaptive admission envelope.
type Profile struct {
	Name                        string  `json:"name"`
	Fallback                    string  `json:"fallback,omitempty"`
	Strict                      bool    `json:"strict"`
	MemoryReservePercent        float64 `json:"memoryReservePercent"`
	MemoryReserveMinBytes       int64   `json:"memoryReserveMinBytes"`
	MemoryReserveMaxBytes       int64   `json:"memoryReserveMaxBytes"`
	NoSwapMemoryReservePercent  float64 `json:"noSwapMemoryReservePercent"`
	NoSwapMemoryReserveMinBytes int64   `json:"noSwapMemoryReserveMinBytes"`
	NoSwapMemoryReserveMaxBytes int64   `json:"noSwapMemoryReserveMaxBytes"`
	DiskReservePercent          float64 `json:"diskReservePercent"`
	DiskReserveMinBytes         int64   `json:"diskReserveMinBytes"`
	DiskReserveMaxBytes         int64   `json:"diskReserveMaxBytes"`
	MaxConcurrency              int     `json:"maxConcurrency"`
	MaxCPUUtilizationPercent    float64 `json:"maxCpuUtilizationPercent"`
}

// Catalog owns the named profile graph.
type Catalog struct {
	DefaultProfile string
	Profiles       map[string]Profile
}

// Resolution is the selected profile and its concrete host thresholds.
type Resolution struct {
	RequestedProfile string   `json:"requestedProfile"`
	ResolvedProfile  string   `json:"resolvedProfile"`
	FallbackChain    []string `json:"fallbackChain"`
	Strict           bool     `json:"strict"`
	Concurrency      int      `json:"concurrency"`
	MemoryReserve    int64    `json:"memoryReserveBytes"`
	DiskReserve      int64    `json:"diskReserveBytes"`
	Decision         string   `json:"decision"`
	ExitCode         int      `json:"exitCode"`
	Retryable        bool     `json:"retryable"`
	Policy           Policy   `json:"-"`
}

// BuiltinCatalog returns deterministic capacity-relative defaults.
func BuiltinCatalog() Catalog {
	return Catalog{DefaultProfile: profileBalanced, Profiles: map[string]Profile{
		profileBalanced: {
			Name: profileBalanced, Fallback: profileConstrained,
			MemoryReservePercent: 15, MemoryReserveMinBytes: GiB, MemoryReserveMaxBytes: 4 * GiB,
			NoSwapMemoryReservePercent: 20, NoSwapMemoryReserveMinBytes: GiB, NoSwapMemoryReserveMaxBytes: 4 * GiB,
			DiskReservePercent: 10, DiskReserveMinBytes: 2 * GiB, DiskReserveMaxBytes: 20 * GiB,
			MaxCPUUtilizationPercent: 85,
		},
		profileConstrained: {
			Name: profileConstrained, Fallback: profileMinimal,
			MemoryReservePercent: 10, MemoryReserveMinBytes: 512 * MiB, MemoryReserveMaxBytes: 2 * GiB,
			NoSwapMemoryReservePercent: 15, NoSwapMemoryReserveMinBytes: 512 * MiB, NoSwapMemoryReserveMaxBytes: 2 * GiB,
			DiskReservePercent: 5, DiskReserveMinBytes: GiB, DiskReserveMaxBytes: 8 * GiB,
			MaxConcurrency: 2, MaxCPUUtilizationPercent: 92,
		},
		profileMinimal: {
			Name:                 profileMinimal,
			MemoryReservePercent: 5, MemoryReserveMinBytes: 128 * MiB, MemoryReserveMaxBytes: 512 * MiB,
			NoSwapMemoryReservePercent: 10, NoSwapMemoryReserveMinBytes: 256 * MiB, NoSwapMemoryReserveMaxBytes: 768 * MiB,
			DiskReservePercent: 2, DiskReserveMinBytes: HardDiskFloorBytes, DiskReserveMaxBytes: GiB,
			MaxConcurrency: 1, MaxCPUUtilizationPercent: 98,
		},
	}}
}

func clampPercent(capacity int64, percentage float64, minimum, maximum int64) int64 {
	value := int64(math.Ceil(float64(capacity) * percentage / 100))
	return min(maximum, max(minimum, value))
}

func sampleMemoryLimit(sample Sample) int64 {
	if sample.EffectiveMemoryLimitBytes > 0 {
		return sample.EffectiveMemoryLimitBytes
	}
	return sample.PhysicalMemoryBytes
}

func profilePolicy(profile Profile, sample Sample) (Policy, int64, int64, int) {
	memoryCapacity := sampleMemoryLimit(sample)
	memoryReserve := clampPercent(memoryCapacity, profile.MemoryReservePercent, profile.MemoryReserveMinBytes, profile.MemoryReserveMaxBytes)
	if sample.SwapState == swapUnavailable {
		memoryReserve = clampPercent(memoryCapacity, profile.NoSwapMemoryReservePercent, profile.NoSwapMemoryReserveMinBytes, profile.NoSwapMemoryReserveMaxBytes)
	}
	diskCapacity := int64(0)
	if sample.DiskTotalBytes != nil {
		diskCapacity = *sample.DiskTotalBytes
	} else if sample.DiskFreeBytes != nil {
		diskCapacity = *sample.DiskFreeBytes
	}
	diskReserve := clampPercent(diskCapacity, profile.DiskReservePercent, profile.DiskReserveMinBytes, profile.DiskReserveMaxBytes)
	parallelism := max(1, sample.AvailableParallelism)
	concurrency := max(1, parallelism-1)
	if profile.MaxConcurrency > 0 {
		concurrency = min(concurrency, profile.MaxConcurrency)
	}
	policy := DevelopmentPolicy
	policy.AdmissionMemoryBytes = memoryReserve
	policy.CriticalMemoryBytes = max(64*MiB, memoryReserve/2)
	policy.DiskWarningBytes = diskReserve
	policy.DiskCriticalBytes = HardDiskFloorBytes
	policy.MaxCPUUtilizationPercent = profile.MaxCPUUtilizationPercent
	policy.SwapOutWarningBytes = clampPercent(memoryCapacity, .4, 64*MiB, 128*MiB)
	policy.SwapOutCriticalBytes = clampPercent(memoryCapacity, 1.6, 256*MiB, 512*MiB)
	policy.CompressorWarningPayloadBytes = clampPercent(memoryCapacity, 37.5, 0, math.MaxInt64)
	policy.CompressorWarningGrowthBytes = clampPercent(memoryCapacity, 3.125, 0, math.MaxInt64)
	policy.CompressorCriticalPayloadBytes = clampPercent(memoryCapacity, 50, 0, math.MaxInt64)
	policy.CompressorCriticalGrowthBytes = clampPercent(memoryCapacity, 6.25, 0, math.MaxInt64)
	return policy, memoryReserve, diskReserve, concurrency
}

func profileFits(sample Sample, policy Policy) bool {
	available := availableMemory(sample)
	cpuFits := sample.CPUUtilizationPercent == nil || CPUAdmissionReady(sample, policy)
	return available != nil && *available >= policy.AdmissionMemoryBytes && sample.DiskFreeBytes != nil && *sample.DiskFreeBytes >= policy.DiskWarningBytes && cpuFits
}

// Resolve chooses a concrete profile for one sample and task class.
func (catalog Catalog) Resolve(requested, taskClass string, sample Sample) (Resolution, error) {
	if requested == "" {
		requested = catalog.DefaultProfile
	}
	if requested == "" {
		requested = profileBalanced
	}
	strictClass := taskClass == "transactional" || taskClass == "release"
	seen := map[string]bool{}
	chain := []string{}
	current := requested
	for current != "" {
		if seen[current] {
			return Resolution{}, fmt.Errorf("profile fallback cycle at %q", current)
		}
		seen[current] = true
		profile, exists := catalog.Profiles[current]
		if !exists {
			return Resolution{}, fmt.Errorf("unknown resource profile %q", current)
		}
		chain = append(chain, current)
		policy, memoryReserve, diskReserve, concurrency := profilePolicy(profile, sample)
		resolution := Resolution{
			RequestedProfile: requested, ResolvedProfile: current, FallbackChain: append([]string(nil), chain...),
			Strict: strictClass || profile.Strict, Concurrency: concurrency, MemoryReserve: memoryReserve,
			DiskReserve: diskReserve, Decision: "run", Policy: policy,
		}
		if sample.DiskFreeBytes == nil || *sample.DiskFreeBytes < HardDiskFloorBytes {
			resolution.Decision, resolution.ExitCode = "cleanup", 73
			return resolution, nil
		}
		fits := profileFits(sample, policy)
		if fits || current == profileMinimal && !resolution.Strict {
			if !fits {
				resolution.Policy.AdmissionMemoryBytes = resolution.Policy.CriticalMemoryBytes
				resolution.Policy.DiskWarningBytes = HardDiskFloorBytes
			}
			return resolution, nil
		}
		if resolution.Strict {
			resolution.Decision, resolution.ExitCode = "replan", ReplanRequiredExitCode
			return resolution, nil
		}
		current = profile.Fallback
	}
	return Resolution{}, errors.New("resource profile has no usable fallback")
}
