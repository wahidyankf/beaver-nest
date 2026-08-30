package guard

import core "github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/policy"

const (
	// GiB is one binary gibibyte.
	GiB = core.GiB
	// MiB is one binary mebibyte.
	MiB = core.MiB
	// ReplanRequiredExitCode indicates strict configuration or capacity incompatibility.
	ReplanRequiredExitCode = core.ReplanRequiredExitCode
)

type (
	// Sample is one host resource observation.
	Sample = core.Sample
	// CPUState contains cumulative CPU counters used to calculate utilization.
	CPUState = core.CPUState
	// Reading combines a sample with the counters needed for the next collection.
	Reading = core.Reading
	// Collector produces host readings for an admission policy.
	Collector = core.Collector
	// Policy defines resource thresholds and timing windows.
	Policy = core.Policy
	// Assessment classifies the latest resource evidence.
	Assessment = core.Assessment
	// ReleaseSummary contains aggregate release-monitor evidence.
	ReleaseSummary = core.ReleaseSummary
	// Profile defines one adaptive admission envelope.
	Profile = core.Profile
	// Catalog owns the named resource profiles.
	Catalog = core.Catalog
	// Resolution is the selected concrete resource profile.
	Resolution = core.Resolution
)

// DevelopmentPolicy is the repository's canonical guarded-development policy.
var DevelopmentPolicy = core.DevelopmentPolicy

// BuiltinCatalog returns the capacity-relative default profiles.
func BuiltinCatalog() Catalog { return core.BuiltinCatalog() }

// EssentialReadingsValid reports whether a sample contains required safe-admission evidence.
func EssentialReadingsValid(sample Sample) bool { return core.EssentialReadingsValid(sample) }

// MemoryState classifies memory evidence as normal, warning, or critical.
func MemoryState(sample Sample, policy Policy) string { return core.MemoryState(sample, policy) }

// CPUAdmissionReady reports whether current utilization preserves reserved execution units.
func CPUAdmissionReady(sample Sample, policy Policy) bool {
	return core.CPUAdmissionReady(sample, policy)
}

// ResourceAssessment classifies current and trend-based evidence.
func ResourceAssessment(samples []Sample, policy Policy) Assessment {
	return core.ResourceAssessment(samples, policy)
}

// AdmissionReady requires safe resource state and consecutive CPU evidence.
func AdmissionReady(samples []Sample, policy Policy) bool {
	return core.AdmissionReady(samples, policy)
}

// Percentile returns the nearest-rank finite percentile, or nil for no finite values.
func Percentile(values []float64, proportion float64) *float64 {
	return core.Percentile(values, proportion)
}

// ReleaseHeadroomAvailable validates aggregate release capacity.
func ReleaseHeadroomAvailable(summary ReleaseSummary) bool {
	return core.ReleaseHeadroomAvailable(summary)
}

// ReleaseMemoryAvailable reports whether one sample preserves release memory headroom.
func ReleaseMemoryAvailable(sample Sample) bool { return core.ReleaseMemoryAvailable(sample) }
