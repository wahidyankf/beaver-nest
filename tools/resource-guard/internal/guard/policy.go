package guard

import core "github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/policy"

const (
	GiB = core.GiB
	MiB = core.MiB
)

type Sample = core.Sample
type CPUState = core.CPUState
type Reading = core.Reading
type Collector = core.Collector
type Policy = core.Policy
type Assessment = core.Assessment
type ReleaseSummary = core.ReleaseSummary

var DevelopmentPolicy = core.DevelopmentPolicy

func EssentialReadingsValid(sample Sample) bool       { return core.EssentialReadingsValid(sample) }
func MemoryState(sample Sample, policy Policy) string { return core.MemoryState(sample, policy) }
func CPUAdmissionReady(sample Sample, policy Policy) bool {
	return core.CPUAdmissionReady(sample, policy)
}
func ResourceAssessment(samples []Sample, policy Policy) Assessment {
	return core.ResourceAssessment(samples, policy)
}
func AdmissionReady(samples []Sample, policy Policy) bool {
	return core.AdmissionReady(samples, policy)
}
func Percentile(values []float64, proportion float64) *float64 {
	return core.Percentile(values, proportion)
}
func ReleaseHeadroomAvailable(summary ReleaseSummary) bool {
	return core.ReleaseHeadroomAvailable(summary)
}
func ReleaseMemoryAvailable(sample Sample) bool { return core.ReleaseMemoryAvailable(sample) }
