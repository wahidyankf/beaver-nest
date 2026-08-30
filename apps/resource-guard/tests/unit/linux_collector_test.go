//go:build linux

package unit_test

import (
	"errors"
	"testing"
	"time"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/guard"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/host"
)

func TestLinuxCollectorUsesCgroupCapacityAndAllowsNoSwap(t *testing.T) {
	files := map[string]string{
		"/proc/meminfo":                                  "MemTotal: 16777216 kB\nMemAvailable: 8388608 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n",
		"/proc/stat":                                     "cpu 10 0 10 80 0\n",
		"/proc/self/cgroup":                              "0::/actions/job\n",
		"/sys/fs/cgroup/actions/job/memory.max":          "4294967296\n",
		"/sys/fs/cgroup/actions/job/memory.high":         "max\n",
		"/sys/fs/cgroup/actions/job/memory.current":      "1073741824\n",
		"/sys/fs/cgroup/actions/job/memory.swap.max":     "0\n",
		"/sys/fs/cgroup/actions/job/memory.swap.current": "0\n",
		"/sys/fs/cgroup/actions/job/cpu.max":             "200000 100000\n",
		"/sys/fs/cgroup/actions/job/memory.pressure":     "some avg10=0.00 avg60=0.00 total=0\nfull avg10=0.00 avg60=0.00 total=0\n",
		"/sys/fs/cgroup/actions/job/memory.events":       "oom 0\noom_kill 0\n",
		"/proc/vmstat":                                   "pswpin 3\npswpout 4\n",
	}
	read := func(path string) ([]byte, error) {
		value, exists := files[path]
		if !exists {
			return nil, errors.New("fixture path is unavailable")
		}
		return []byte(value), nil
	}
	collector := host.SystemCollector{ReadFile: read, Now: func() time.Time { return time.Unix(0, 0) }}
	reading, err := collector.Collect(nil, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if reading.Sample.Platform != "linux" || reading.Sample.EffectiveMemoryLimitBytes != 4*guard.GiB || reading.Sample.AvailableMemoryBytes == nil || *reading.Sample.AvailableMemoryBytes != 3*guard.GiB || reading.Sample.AvailableParallelism != 2 || reading.Sample.SwapState != "unavailable" {
		t.Fatalf("unexpected Linux sample %+v", reading.Sample)
	}
	files["/proc/stat"] = "cpu 20 0 20 140 0\n"
	second, err := collector.Collect(reading.CPUState, t.TempDir())
	if err != nil || second.Sample.CPUUtilizationPercent == nil || *second.Sample.CPUUtilizationPercent != 40 {
		t.Fatalf("unexpected Linux CPU sample %+v error=%v", second.Sample, err)
	}
}
