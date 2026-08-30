package host

import (
	"errors"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"
)

// LinuxMemory contains normalized /proc/meminfo values.
type LinuxMemory struct {
	Total, Available, SwapTotal, SwapFree int64
}

// PSI contains one pressure stall average pair.
type PSI struct {
	SomeAvg10, FullAvg10 float64
}

// ParseMemInfo parses the required Linux memory capacity fields.
func ParseMemInfo(data string) (LinuxMemory, error) {
	values := map[string]int64{}
	present := map[string]bool{}
	for line := range strings.Lines(data) {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		name := strings.TrimSuffix(fields[0], ":")
		value, err := strconv.ParseInt(fields[1], 10, 64)
		if err != nil || value < 0 {
			return LinuxMemory{}, fmt.Errorf("invalid meminfo field %q", name)
		}
		if len(fields) > 2 && fields[2] == "kB" {
			value *= 1024
		}
		values[name] = value
		present[name] = true
	}
	if !present["MemTotal"] || !present["MemAvailable"] || values["MemTotal"] <= 0 || values["MemAvailable"] < 0 {
		return LinuxMemory{}, errors.New("MemTotal or MemAvailable is unavailable")
	}
	return LinuxMemory{values["MemTotal"], values["MemAvailable"], values["SwapTotal"], values["SwapFree"]}, nil
}

// ParseProcStat parses aggregate Linux CPU counters.
func ParseProcStat(data string) (CPUState, error) {
	for line := range strings.Lines(data) {
		fields := strings.Fields(line)
		if len(fields) < 5 || fields[0] != "cpu" {
			continue
		}
		state := make(CPUState, 0, len(fields)-1)
		for _, field := range fields[1:] {
			value, err := strconv.ParseUint(field, 10, 64)
			if err != nil {
				return nil, errors.New("aggregate CPU counters are invalid")
			}
			state = append(state, value)
		}
		return state, nil
	}
	return nil, errors.New("aggregate CPU counters are unavailable")
}

func parsePSILine(line string) (float64, error) {
	for field := range strings.FieldsSeq(line) {
		if raw, found := strings.CutPrefix(field, "avg10="); found {
			value, err := strconv.ParseFloat(raw, 64)
			if err != nil || value < 0 || value > 100 {
				return 0, errors.New("PSI avg10 is invalid")
			}
			return value, nil
		}
	}
	return 0, errors.New("PSI avg10 is unavailable")
}

// ParsePSI parses Linux pressure stall averages.
func ParsePSI(data string) (PSI, error) {
	result := PSI{}
	foundSome, foundFull := false, false
	for line := range strings.Lines(data) {
		switch {
		case strings.HasPrefix(line, "some "):
			value, err := parsePSILine(line)
			if err != nil {
				return PSI{}, err
			}
			result.SomeAvg10, foundSome = value, true
		case strings.HasPrefix(line, "full "):
			value, err := parsePSILine(line)
			if err != nil {
				return PSI{}, err
			}
			result.FullAvg10, foundFull = value, true
		}
	}
	if !foundSome {
		return PSI{}, errors.New("PSI some evidence is unavailable")
	}
	if !foundFull {
		result.FullAvg10 = 0
	}
	return result, nil
}

// ParseMemoryEvents parses cumulative cgroup memory event counters.
func ParseMemoryEvents(data string) map[string]int64 {
	result := map[string]int64{}
	for line := range strings.Lines(data) {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		value, err := strconv.ParseInt(fields[1], 10, 64)
		if err == nil && value >= 0 {
			result[fields[0]] = value
		}
	}
	return result
}

// ParseCgroupLimit parses a finite cgroup byte limit.
func ParseCgroupLimit(data []byte) (int64, bool) {
	value := strings.TrimSpace(string(data))
	if value == "" || value == "max" {
		return 0, false
	}
	parsed, err := strconv.ParseInt(value, 10, 64)
	return parsed, err == nil && parsed >= 0
}

// EffectiveMemoryLimit applies finite cgroup high and maximum limits to host memory.
func EffectiveMemoryLimit(hostBytes, maximumBytes, highBytes int64) int64 {
	result := hostBytes
	for _, limit := range []int64{maximumBytes, highBytes} {
		if limit > 0 && limit < result {
			result = limit
		}
	}
	return result
}

// ParseCPUMax converts a cgroup v2 CPU quota into integer execution units.
func ParseCPUMax(data string) (int, bool) {
	fields := strings.Fields(data)
	if len(fields) != 2 || fields[0] == "max" {
		return 0, false
	}
	quota, quotaError := strconv.ParseInt(fields[0], 10, 64)
	period, periodError := strconv.ParseInt(fields[1], 10, 64)
	if quotaError != nil || periodError != nil || quota <= 0 || period <= 0 {
		return 0, false
	}
	return max(1, int(quota/period)), true
}

// CgroupRoot resolves the unified cgroup v2 path for the current process.
func CgroupRoot(data string) string {
	for line := range strings.Lines(data) {
		if relative, found := strings.CutPrefix(line, "0::"); found {
			cleaned := filepath.Clean("/" + strings.TrimSpace(relative))
			return filepath.Join("/sys/fs/cgroup", cleaned)
		}
	}
	return "/sys/fs/cgroup"
}

// ParseLinuxVMStat returns cumulative Linux swap-in and swap-out page counters.
func ParseLinuxVMStat(data string) (int64, int64) {
	values := map[string]int64{}
	for line := range strings.Lines(data) {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		value, err := strconv.ParseInt(fields[1], 10, 64)
		if err == nil {
			values[fields[0]] = value
		}
	}
	return values["pswpin"], values["pswpout"]
}
