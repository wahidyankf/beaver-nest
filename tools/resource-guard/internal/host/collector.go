package host

import (
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/guard"
)

type (
	// CPUState contains cumulative CPU counters used for utilization deltas.
	CPUState = guard.CPUState
	// Reading combines one host sample with its CPU counters.
	Reading = guard.Reading
)

// CommandRunner executes one local host probe.
type CommandRunner func(string, ...string) ([]byte, error)

// FileReader reads one local kernel evidence file.
type FileReader func(string) ([]byte, error)

// SystemCollector gathers platform metrics using system calls and local probes.
type SystemCollector struct {
	Run      CommandRunner
	ReadFile FileReader
	Now      func() time.Time
}

var (
	percentagePattern = regexp.MustCompile(`free percentage:\s*(\d+)%`)
	pageSizePattern   = regexp.MustCompile(`page size of (\d+) bytes`)
	swapPattern       = regexp.MustCompile(`total = ([\d.]+)M\s+used = ([\d.]+)M\s+free = ([\d.]+)M`)
)

// ParseAvailableEstimate converts memory_pressure free percentage into bytes.
func ParseAvailableEstimate(output string, physicalBytes int64) *int64 {
	match := percentagePattern.FindStringSubmatch(output)
	if len(match) != 2 {
		return nil
	}
	percentage, err := strconv.ParseInt(match[1], 10, 64)
	if err != nil || percentage < 0 || percentage > 100 {
		return nil
	}
	value := physicalBytes * percentage / 100
	return &value
}

// VMStat contains the vm_stat counters needed by resource policy.
type VMStat struct {
	PageSizeBytes, CompressorStoredPages, CompressorOccupiedPages, SwapIns, SwapOuts int64
}

// ParseVMStat parses macOS compressor and swap page counters.
func ParseVMStat(output string) *VMStat {
	pageMatch := pageSizePattern.FindStringSubmatch(output)
	if len(pageMatch) != 2 {
		return nil
	}
	pageSize, err := strconv.ParseInt(pageMatch[1], 10, 64)
	if err != nil {
		return nil
	}
	value := func(label string) (int64, bool) {
		pattern := regexp.MustCompile(regexp.QuoteMeta(label) + `:\s+(\d+)\.`)
		match := pattern.FindStringSubmatch(output)
		if len(match) != 2 {
			return 0, false
		}
		parsed, parseError := strconv.ParseInt(match[1], 10, 64)
		return parsed, parseError == nil
	}
	stored, ok1 := value("Pages stored in compressor")
	occupied, ok2 := value("Pages occupied by compressor")
	ins, ok3 := value("Swapins")
	outs, ok4 := value("Swapouts")
	if !ok1 || !ok2 || !ok3 || !ok4 {
		return nil
	}
	return &VMStat{pageSize, stored, occupied, ins, outs}
}

// SwapUsage contains swap capacity values in bytes.
type SwapUsage struct{ Total, Used, Free int64 }

// ParseSwapUsage parses the macOS vm.swapusage response.
func ParseSwapUsage(output string) *SwapUsage {
	match := swapPattern.FindStringSubmatch(output)
	if len(match) != 4 {
		return nil
	}
	values := make([]int64, 3)
	for index, text := range match[1:] {
		value, err := strconv.ParseFloat(text, 64)
		if err != nil {
			return nil
		}
		values[index] = int64(value * float64(guard.MiB))
	}
	return &SwapUsage{values[0], values[1], values[2]}
}

// CPUUtilization calculates aggregate utilization from cumulative CPU counters.
func CPUUtilization(previous, current CPUState) *float64 {
	if len(previous) == 0 || len(previous) != len(current) || len(current) < 4 {
		return nil
	}
	var total, idle uint64
	for index, after := range current {
		if after < previous[index] {
			return nil
		}
		delta := after - previous[index]
		total += delta
		if index == 3 {
			idle += delta
		}
	}
	if total == 0 {
		return nil
	}
	value := float64(total-idle) * 100 / float64(total)
	return &value
}

// ParseProcessCPU normalizes summed process CPU use by available parallelism.
func ParseProcessCPU(output string, parallelism int) *float64 {
	if parallelism <= 0 {
		return nil
	}
	total := 0.0
	for field := range strings.FieldsSeq(output) {
		value, err := strconv.ParseFloat(strings.TrimSuffix(field, "%"), 64)
		if err != nil || value < 0 {
			return nil
		}
		total += value
	}
	value := min(100, total/float64(parallelism))
	return &value
}
