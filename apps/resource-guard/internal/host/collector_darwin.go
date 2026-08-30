//go:build darwin

package host

import (
	"errors"
	"fmt"
	"math"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/guard"
	"golang.org/x/sys/unix"
)

func command(name string, arguments ...string) ([]byte, error) {
	return exec.Command(name, arguments...).Output()
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
	if value == nil || *value != 0 && *value != 1 {
		return nil
	}
	converted := *value == 1
	return &converted
}

func int64FromUint64(value uint64) (int64, bool) {
	if value > math.MaxInt64 {
		return 0, false
	}
	return int64(value), true
}

func applyDarwinSwap(sample *guard.Sample, output []byte, err error) {
	if err != nil {
		return
	}
	parsed := ParseSwapUsage(strings.TrimSpace(string(output)))
	if parsed == nil {
		return
	}
	sample.SwapTotalBytes, sample.SwapUsedBytes, sample.SwapFreeBytes = &parsed.Total, &parsed.Used, &parsed.Free
	switch {
	case parsed.Total == 0:
		sample.SwapState = "unavailable"
	case parsed.Used > 0:
		sample.SwapState = "active"
	default:
		sample.SwapState = "idle"
	}
}

// Collect gathers one macOS reading while treating compressor and swap as capabilities.
func (collector SystemCollector) Collect(previous CPUState, diskPath string) (Reading, error) {
	run := collector.Run
	if run == nil {
		run = command
	}
	now := collector.Now
	if now == nil {
		now = time.Now
	}
	physical, err := unix.SysctlUint64("hw.memsize")
	if err != nil {
		return Reading{}, fmt.Errorf("read physical memory: %w", err)
	}
	physicalBytes, valid := int64FromUint64(physical)
	if !valid {
		return Reading{}, errors.New("physical memory exceeds supported range")
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
	diskFree, diskTotal, diskError := diskCapacity(diskPath)
	if diskError != nil {
		return Reading{}, fmt.Errorf("read disk capacity: %w", diskError)
	}
	var estimate *int64
	if pressureError == nil {
		estimate = ParseAvailableEstimate(string(pressureOutput), physicalBytes)
	}
	if estimate == nil {
		return Reading{}, errors.New("available memory estimate is unavailable")
	}
	sample := guard.Sample{
		SchemaVersion: 3, MeasuredAt: now().UTC().Format(time.RFC3339Nano), Platform: "darwin",
		Capabilities: []string{"compressor", "memory-pressure", "swap"}, EffectiveMemoryLimitBytes: physicalBytes,
		AvailableMemoryBytes: estimate, AvailableNonCompressedEstimateBytes: estimate,
		MemoryPressureLevel: levelPointer(pressureLevel), CompressorAvailable: boolPointer(compressorAvailable),
		CompressorPayloadBytes: compressorPayload, PhysicalMemoryBytes: physicalBytes, AvailableParallelism: parallelism,
		DiskFreeBytes: diskFree, DiskTotalBytes: diskTotal, SwapState: "unknown",
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
	applyDarwinSwap(&sample, swapOutput, swapError)
	return Reading{CPUState: previous, Sample: sample}, nil
}
