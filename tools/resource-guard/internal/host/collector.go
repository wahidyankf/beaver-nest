package host

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/guard"
	"golang.org/x/sys/unix"
)

type CPUState = guard.CPUState
type Reading = guard.Reading

type CommandRunner func(string, ...string) ([]byte, error)

type SystemCollector struct {
	Run CommandRunner
	Now func() time.Time
}

func command(name string, arguments ...string) ([]byte, error) {
	return exec.Command(name, arguments...).Output()
}

var (
	percentagePattern = regexp.MustCompile(`free percentage:\s*(\d+)%`)
	pageSizePattern   = regexp.MustCompile(`page size of (\d+) bytes`)
	swapPattern       = regexp.MustCompile(`total = ([\d.]+)M\s+used = ([\d.]+)M\s+free = ([\d.]+)M`)
)

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

type VMStat struct {
	PageSizeBytes, CompressorStoredPages, CompressorOccupiedPages, SwapIns, SwapOuts int64
}

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

type SwapUsage struct{ Total, Used, Free int64 }

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

func ParseProcessCPU(output string, parallelism int) *float64 {
	if parallelism <= 0 {
		return nil
	}
	total := 0.0
	for _, field := range strings.Fields(output) {
		value, err := strconv.ParseFloat(strings.TrimSuffix(field, "%"), 64)
		if err != nil || value < 0 {
			return nil
		}
		total += value
	}
	value := min(100, total/float64(parallelism))
	return &value
}

func parseSysctlInt(output []byte, err error) *int64 {
	if err != nil {
		return nil
	}
	value, parseError := strconv.ParseInt(strings.TrimSpace(string(output)), 10, 64)
	if parseError != nil {
		return nil
	}
	return &value
}
func levelPointer(value *int64) *int {
	if value == nil {
		return nil
	}
	converted := int(*value)
	return &converted
}
func boolPointer(value *int64) *bool {
	if value == nil || (*value != 0 && *value != 1) {
		return nil
	}
	converted := *value == 1
	return &converted
}

func (collector SystemCollector) Collect(previous CPUState, diskPath string) (Reading, error) {
	run := collector.Run
	if run == nil {
		run = command
	}
	now := collector.Now
	if now == nil {
		now = time.Now
	}
	physical, physicalError := unix.SysctlUint64("hw.memsize")
	if physicalError != nil {
		return Reading{}, fmt.Errorf("read physical memory: %w", physicalError)
	}
	parallelism := runtime.NumCPU()
	cpuOutput, cpuError := run("ps", "-A", "-o", "%cpu=")
	pressureOutput, pressureError := run("memory_pressure", "-Q")
	vmOutput, vmError := run("vm_stat")
	swapOutput, swapError := run("sysctl", "-n", "vm.swapusage")
	pressureLevelOutput, pressureLevelError := run("sysctl", "-n", "kern.memorystatus_vm_pressure_level")
	compressorAvailableOutput, compressorAvailableError := run("sysctl", "-n", "vm.compressor_available")
	compressorPayloadOutput, compressorPayloadError := run("sysctl", "-n", "vm.compressor_bytes_used")
	pressureLevel := parseSysctlInt(pressureLevelOutput, pressureLevelError)
	compressorAvailable := parseSysctlInt(compressorAvailableOutput, compressorAvailableError)
	compressorPayload := parseSysctlInt(compressorPayloadOutput, compressorPayloadError)
	var disk unix.Statfs_t
	diskError := unix.Statfs(diskPath, &disk)
	var diskFree *int64
	if diskError == nil {
		value := int64(disk.Bavail) * int64(disk.Bsize)
		diskFree = &value
	}
	var estimate *int64
	if pressureError == nil {
		estimate = ParseAvailableEstimate(string(pressureOutput), int64(physical))
	}
	sample := guard.Sample{
		SchemaVersion: 2, MeasuredAt: now().UTC().Format(time.RFC3339Nano),
		AvailableNonCompressedEstimateBytes: estimate,
		MemoryPressureLevel:                 levelPointer(pressureLevel),
		CompressorAvailable:                 boolPointer(compressorAvailable),
		CompressorPayloadBytes:              compressorPayload,
		PhysicalMemoryBytes:                 int64(physical), AvailableParallelism: parallelism,
		CPUUtilizationPercent: nil, DiskFreeBytes: diskFree,
	}
	if cpuError == nil {
		sample.CPUUtilizationPercent = ParseProcessCPU(string(cpuOutput), parallelism)
	}
	if vmError == nil {
		if parsed := ParseVMStat(string(vmOutput)); parsed != nil {
			sample.PageSizeBytes = &parsed.PageSizeBytes
			sample.CompressorStoredPages = &parsed.CompressorStoredPages
			sample.CompressorOccupiedPages = &parsed.CompressorOccupiedPages
			sample.SwapIns = &parsed.SwapIns
			sample.SwapOuts = &parsed.SwapOuts
		}
	}
	if swapError == nil {
		if parsed := ParseSwapUsage(strings.TrimSpace(string(swapOutput))); parsed != nil {
			sample.SwapTotalBytes = &parsed.Total
			sample.SwapUsedBytes = &parsed.Used
			sample.SwapFreeBytes = &parsed.Free
		}
	}
	return Reading{CPUState: previous, Sample: sample}, nil
}

func DefaultEvidenceRoot(environment map[string]string) string {
	if root := environment["BNEST_RESOURCE_ROOT"]; root != "" {
		return root
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return home + "/bnest/runtime/resource-guard"
}
