package guard

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"time"
)

const maximumEvidenceBytes int64 = 50 * 1024 * 1024

// CleanupEvidence removes expired or excess evidence while preserving active paths.
func CleanupEvidence(root string, now time.Time, preserve ...string) error {
	if root == "" {
		return errors.New("evidence root is empty")
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return err
	}
	if err := os.Chmod(root, 0o700); err != nil {
		return err
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	preserved := map[string]bool{}
	for _, path := range preserve {
		preserved[path] = true
	}
	type retainedFile struct {
		path     string
		size     int64
		modified time.Time
	}
	retained := []retainedFile{}
	for _, entry := range entries {
		if !entry.Type().IsRegular() {
			continue
		}
		path := filepath.Join(root, entry.Name())
		info, infoError := entry.Info()
		if infoError != nil {
			return infoError
		}
		retention := 7 * 24 * time.Hour
		if filepath.Ext(entry.Name()) == ".json" && len(entry.Name()) >= len(".summary.json") && entry.Name()[len(entry.Name())-len(".summary.json"):] == ".summary.json" {
			retention = 30 * 24 * time.Hour
		}
		if now.Sub(info.ModTime()) > retention && !preserved[path] {
			if removeError := os.Remove(path); removeError != nil {
				return removeError
			}
			continue
		}
		retained = append(retained, retainedFile{path, info.Size(), info.ModTime()})
	}
	sort.Slice(retained, func(i, j int) bool { return retained[i].modified.Before(retained[j].modified) })
	var total int64
	for _, entry := range retained {
		total += entry.size
	}
	for _, entry := range retained {
		if total <= maximumEvidenceBytes {
			break
		}
		if preserved[entry.path] {
			continue
		}
		if removeError := os.Remove(entry.path); removeError != nil {
			return removeError
		}
		total -= entry.size
	}
	return nil
}

// EvidenceWriter appends private samples and produces one bounded summary.
type EvidenceWriter struct {
	outputPath, summaryPath string
	output                  *os.File
	samples                 []Sample
}

// NewEvidenceWriter creates an exclusive evidence stream below root.
func NewEvidenceWriter(root, identifier string) (*EvidenceWriter, error) {
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, err
	}
	if err := os.Chmod(root, 0o700); err != nil {
		return nil, err
	}
	outputPath := filepath.Join(root, identifier+".jsonl")
	output, err := os.OpenFile(outputPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return nil, err
	}
	return &EvidenceWriter{outputPath: outputPath, summaryPath: filepath.Join(root, identifier+".summary.json"), output: output}, nil
}

// Append records one sample in the evidence stream.
func (writer *EvidenceWriter) Append(sample Sample) error {
	encoded, err := json.Marshal(sample)
	if err != nil {
		return err
	}
	if _, err = writer.output.Write(append(encoded, '\n')); err != nil {
		return err
	}
	writer.samples = append(writer.samples, sample)
	return nil
}

// EvidenceSummary captures bounded aggregate evidence for one guarded task.
type EvidenceSummary struct {
	SchemaVersion                          int     `json:"schemaVersion"`
	SampleCount                            int     `json:"sampleCount"`
	TaskClass                              string  `json:"taskClass"`
	Outcome                                string  `json:"outcome"`
	AvailableParallelism                   int     `json:"availableParallelism"`
	AvailableNonCompressedEstimateMinBytes *int64  `json:"availableNonCompressedEstimateMinBytes"`
	MemoryPressureLevelMax                 *int    `json:"memoryPressureLevelMax"`
	CompressorAvailableAll                 bool    `json:"compressorAvailableAll"`
	CompressorPayloadPeakBytes             *int64  `json:"compressorPayloadPeakBytes"`
	CPUUtilizationP95Percent               float64 `json:"cpuUtilizationP95Percent"`
	DiskFreeMinBytes                       *int64  `json:"diskFreeMinBytes"`
	SwapInsDelta                           int64   `json:"swapInsDelta"`
	SwapOutsDelta                          int64   `json:"swapOutsDelta"`
	SwapFreeMinBytes                       *int64  `json:"swapFreeMinBytes"`
	HealthFailures                         int     `json:"healthFailures"`
}

func minInt64(values []*int64) *int64 {
	var result *int64
	for _, value := range values {
		if value != nil && (result == nil || *value < *result) {
			candidate := *value
			result = &candidate
		}
	}
	return result
}

func maxInt64(values []*int64) *int64 {
	var result *int64
	for _, value := range values {
		if value != nil && (result == nil || *value > *result) {
			candidate := *value
			result = &candidate
		}
	}
	return result
}

func maxInt(values []*int) *int {
	var result *int
	for _, value := range values {
		if value != nil && (result == nil || *value > *result) {
			candidate := *value
			result = &candidate
		}
	}
	return result
}

func delta(first, last *int64) int64 {
	if first == nil || last == nil || *last <= *first {
		return 0
	}
	return *last - *first
}

// Finalize closes the sample stream and writes its aggregate summary once.
func (writer *EvidenceWriter) Finalize(taskClass, outcome string, healthFailures int) (EvidenceSummary, error) {
	if writer.output == nil {
		return EvidenceSummary{}, errors.New("evidence writer is closed")
	}
	if err := writer.output.Close(); err != nil {
		return EvidenceSummary{}, err
	}
	writer.output = nil
	summary := EvidenceSummary{SchemaVersion: 2, SampleCount: len(writer.samples), TaskClass: taskClass, Outcome: outcome, HealthFailures: healthFailures, CompressorAvailableAll: true}
	available, levels, payloads, disks, swapFree := []*int64{}, []*int{}, []*int64{}, []*int64{}, []*int64{}
	cpu := []float64{}
	for _, sample := range writer.samples {
		available = append(available, sample.AvailableNonCompressedEstimateBytes)
		levels = append(levels, sample.MemoryPressureLevel)
		payloads = append(payloads, sample.CompressorPayloadBytes)
		disks = append(disks, sample.DiskFreeBytes)
		swapFree = append(swapFree, sample.SwapFreeBytes)
		if sample.CompressorAvailable == nil || !*sample.CompressorAvailable {
			summary.CompressorAvailableAll = false
		}
		if sample.CPUUtilizationPercent != nil {
			cpu = append(cpu, *sample.CPUUtilizationPercent)
		}
	}
	if len(writer.samples) > 0 {
		summary.AvailableParallelism = writer.samples[0].AvailableParallelism
		summary.SwapInsDelta = delta(writer.samples[0].SwapIns, writer.samples[len(writer.samples)-1].SwapIns)
		summary.SwapOutsDelta = delta(writer.samples[0].SwapOuts, writer.samples[len(writer.samples)-1].SwapOuts)
	}
	summary.AvailableNonCompressedEstimateMinBytes = minInt64(available)
	summary.MemoryPressureLevelMax = maxInt(levels)
	summary.CompressorPayloadPeakBytes = maxInt64(payloads)
	summary.DiskFreeMinBytes = minInt64(disks)
	summary.SwapFreeMinBytes = minInt64(swapFree)
	if value := Percentile(cpu, .95); value != nil {
		summary.CPUUtilizationP95Percent = *value
	}
	encoded, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		return EvidenceSummary{}, err
	}
	file, err := os.OpenFile(writer.summaryPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return EvidenceSummary{}, err
	}
	buffer := bufio.NewWriter(file)
	_, writeError := buffer.Write(append(encoded, '\n'))
	flushError := buffer.Flush()
	closeError := file.Close()
	if writeError != nil {
		return EvidenceSummary{}, writeError
	}
	if flushError != nil {
		return EvidenceSummary{}, flushError
	}
	if closeError != nil {
		return EvidenceSummary{}, closeError
	}
	return summary, nil
}

var unsafeIdentifier = regexp.MustCompile(`[^a-zA-Z0-9._-]`)

// EvidenceIdentifier returns a filesystem-safe, process-specific evidence name.
func EvidenceIdentifier(prefix string, now time.Time, pid int) string {
	return unsafeIdentifier.ReplaceAllString(fmt.Sprintf("%s-%d-%d", prefix, now.UnixMilli(), pid), "-")
}
