//go:build linux

package host

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/internal/guard"
)

func readOptional(read FileReader, path string) []byte {
	value, err := read(path)
	if err != nil {
		return nil
	}
	return value
}

// Collect gathers one Linux reading from procfs, cgroup v2, PSI, and statfs.
func (collector SystemCollector) Collect(previous CPUState, diskPath string) (Reading, error) {
	read := collector.ReadFile
	if read == nil {
		read = os.ReadFile
	}
	now := collector.Now
	if now == nil {
		now = time.Now
	}
	memData, err := read("/proc/meminfo")
	if err != nil {
		return Reading{}, fmt.Errorf("read Linux memory: %w", err)
	}
	memory, err := ParseMemInfo(string(memData))
	if err != nil {
		return Reading{}, err
	}
	statData, err := read("/proc/stat")
	if err != nil {
		return Reading{}, fmt.Errorf("read Linux CPU: %w", err)
	}
	currentCPU, err := ParseProcStat(string(statData))
	if err != nil {
		return Reading{}, err
	}
	cgroupData := readOptional(read, "/proc/self/cgroup")
	cgroup := CgroupRoot(string(cgroupData))
	maximum, maximumFinite := ParseCgroupLimit(readOptional(read, filepath.Join(cgroup, "memory.max")))
	high, highFinite := ParseCgroupLimit(readOptional(read, filepath.Join(cgroup, "memory.high")))
	if !maximumFinite {
		maximum = 0
	}
	if !highFinite {
		high = 0
	}
	effective := EffectiveMemoryLimit(memory.Total, maximum, high)
	available := memory.Available
	if current, finite := ParseCgroupLimit(readOptional(read, filepath.Join(cgroup, "memory.current"))); finite && effective > 0 {
		available = min(available, max(int64(0), effective-current))
	}
	parallelism := runtime.NumCPU()
	if quota, finite := ParseCPUMax(string(readOptional(read, filepath.Join(cgroup, "cpu.max")))); finite {
		parallelism = min(parallelism, quota)
	}
	parallelism = max(1, parallelism)
	psiData := readOptional(read, filepath.Join(cgroup, "memory.pressure"))
	if len(psiData) == 0 {
		psiData = readOptional(read, "/proc/pressure/memory")
	}
	var some, full *float64
	pressureLevel := 1
	if psi, psiError := ParsePSI(string(psiData)); psiError == nil {
		some, full = &psi.SomeAvg10, &psi.FullAvg10
		if psi.SomeAvg10 >= 25 || psi.FullAvg10 >= 5 {
			pressureLevel = 4
		} else if psi.SomeAvg10 >= 10 {
			pressureLevel = 2
		}
	}
	events := ParseMemoryEvents(string(readOptional(read, filepath.Join(cgroup, "memory.events"))))
	oom, oomKill := events["oom"], events["oom_kill"]
	swapMax, swapMaxFinite := ParseCgroupLimit(readOptional(read, filepath.Join(cgroup, "memory.swap.max")))
	swapCurrent, swapCurrentFinite := ParseCgroupLimit(readOptional(read, filepath.Join(cgroup, "memory.swap.current")))
	swapState := "idle"
	if memory.SwapTotal == 0 || swapMaxFinite && swapMax == 0 {
		swapState = "unavailable"
	} else if swapCurrentFinite && swapCurrent > 0 || memory.SwapFree < memory.SwapTotal {
		swapState = "active"
	}
	diskFree, diskTotal, diskError := diskCapacity(diskPath)
	if diskError != nil {
		return Reading{}, fmt.Errorf("read disk capacity: %w", diskError)
	}
	pageSize := int64(os.Getpagesize())
	swapIns, swapOuts := ParseLinuxVMStat(string(readOptional(read, "/proc/vmstat")))
	swapUsed := max(int64(0), memory.SwapTotal-memory.SwapFree)
	sample := guard.Sample{
		SchemaVersion: 3, MeasuredAt: now().UTC().Format(time.RFC3339Nano), Platform: "linux",
		Capabilities: []string{"cgroup-v2", "memory-psi"}, EffectiveMemoryLimitBytes: effective,
		AvailableMemoryBytes: &available, PhysicalMemoryBytes: memory.Total, AvailableParallelism: parallelism,
		CPUUtilizationPercent: CPUUtilization(previous, currentCPU), DiskFreeBytes: diskFree, DiskTotalBytes: diskTotal,
		MemoryPressureLevel: &pressureLevel, PageSizeBytes: &pageSize, SwapIns: &swapIns, SwapOuts: &swapOuts,
		SwapTotalBytes: &memory.SwapTotal, SwapUsedBytes: &swapUsed, SwapFreeBytes: &memory.SwapFree, SwapState: swapState,
		MemoryPSISomeAvg10: some, MemoryPSIFullAvg10: full, OOMEvents: &oom, OOMKillEvents: &oomKill,
	}
	return Reading{CPUState: currentCPU, Sample: sample}, nil
}
