package support

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/cli"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/guard"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/host"
	releaseguard "github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/release"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/tests/contract"
)

type sequenceCollector struct {
	samples []guard.Sample
	index   int
}

func (collector *sequenceCollector) Collect(previous guard.CPUState, _ string) (guard.Reading, error) {
	if len(collector.samples) == 0 {
		return guard.Reading{}, errors.New("no samples")
	}
	index := min(collector.index, len(collector.samples)-1)
	collector.index++
	return guard.Reading{CPUState: previous, Sample: collector.samples[index]}, nil
}

// Driver carries isolated scenario state for one adapter suite.
type Driver struct {
	mode                string
	samples             []guard.Sample
	assessment          guard.Assessment
	admitted, accepted  bool
	exitCode            int
	output, errorOutput string
	binary, summaryPath string
	temporaryPaths      []string
	lifecycleOK         bool
	cacheRoot           string
	historicalCaches    []string
	lintConfiguration   string
	lintCommand         string
	strictAdapters      bool
	approvedExemptions  bool
	serialCompliance    bool
	e2ePlacement        bool
	resolution          guard.Resolution
	requestedProfile    string
	taskClass           string
	effectiveMemory     int64
	configPath          string
	privateArtifacts    bool
	exampleTracked      bool
	applicationLayout   bool
	leaseRoot           string
	leaseHolder         int
	heavySession        *guard.Session
	serviceSessions     []*guard.Session
	inheritedSessions   bool
	forceStopElapsed    time.Duration
	terminationSignals  int
}

// NewDriver returns isolated scenario state for one behavior adapter.
func NewDriver(adapter contract.Adapter) *Driver {
	return &Driver{mode: adapter.Name}
}

func healthySample(at time.Time) guard.Sample {
	return guard.Sample{SchemaVersion: 3, MeasuredAt: at.UTC().Format(time.RFC3339Nano), Platform: "darwin", Capabilities: []string{"compressor", "memory-pressure", "swap"}, EffectiveMemoryLimitBytes: 32 * guard.GiB, AvailableMemoryBytes: new(12 * guard.GiB), AvailableNonCompressedEstimateBytes: new(12 * guard.GiB), MemoryPressureLevel: new(1), CompressorAvailable: new(true), CompressorPayloadBytes: new(7 * guard.GiB), PhysicalMemoryBytes: 32 * guard.GiB, AvailableParallelism: 8, CPUUtilizationPercent: new(20.0), DiskFreeBytes: new(40 * guard.GiB), DiskTotalBytes: new(512 * guard.GiB), PageSizeBytes: new(int64(16_384)), SwapIns: new(int64(10)), SwapOuts: new(int64(20)), SwapFreeBytes: new(2 * guard.GiB), SwapState: "idle"}
}

func (driver *Driver) reset() {
	driver.cleanup()
	mode := driver.mode
	*driver = Driver{mode: mode}
	if mode == contract.E2E {
		driver.binary = os.Getenv("RESOURCE_GUARD_BIN")
	}
}

func (driver *Driver) cleanup() {
	for _, path := range driver.temporaryPaths {
		_ = os.RemoveAll(path)
	}
	driver.temporaryPaths = nil
}

// Close removes temporary scenario resources.
func (driver *Driver) Close() { driver.cleanup() }

func toolRoot() string { return filepath.Clean(filepath.Join("..", "..")) }

func environmentWith(values map[string]string) []string {
	prefixes := make([]string, 0, len(values))
	for name := range values {
		prefixes = append(prefixes, name+"=")
	}
	environment := make([]string, 0, len(os.Environ())+len(values))
	for _, value := range os.Environ() {
		replaced := false
		for _, prefix := range prefixes {
			if strings.HasPrefix(value, prefix) {
				replaced = true
				break
			}
		}
		if !replaced {
			environment = append(environment, value)
		}
	}
	for name, value := range values {
		environment = append(environment, name+"="+value)
	}
	return environment
}

func (driver *Driver) threeHealthy() {
	base := time.Unix(0, 0)
	driver.samples = []guard.Sample{healthySample(base), healthySample(base.Add(time.Second)), healthySample(base.Add(2 * time.Second))}
}

func (driver *Driver) swapGrowth() {
	first := healthySample(time.Unix(0, 0))
	second := healthySample(time.Unix(15, 0))
	first.SwapOuts = new(int64(0))
	second.SwapOuts = new(128 * guard.MiB / 16_384)
	driver.samples = []guard.Sample{first, second}
}

func (driver *Driver) compressorGrowth() {
	first := healthySample(time.Unix(0, 0))
	second := healthySample(time.Unix(15, 0))
	first.CompressorPayloadBytes = new(11 * guard.GiB)
	second.CompressorPayloadBytes = new(12 * guard.GiB)
	driver.samples = []guard.Sample{first, second}
}

func (driver *Driver) assessAdmission() {
	if len(driver.samples) == 0 {
		driver.assessment = guard.ResourceAssessment(nil, guard.DevelopmentPolicy)
		return
	}
	resolution, err := guard.BuiltinCatalog().Resolve(driver.requestedProfile, driver.taskClass, driver.samples[len(driver.samples)-1])
	if err != nil {
		driver.errorOutput = err.Error()
		driver.exitCode = guard.ReplanRequiredExitCode
		return
	}
	driver.resolution = resolution
	driver.exitCode = resolution.ExitCode
	driver.assessment = guard.ResourceAssessment(driver.samples, resolution.Policy)
	driver.admitted = resolution.ExitCode == 0 && guard.AdmissionReady(driver.samples, resolution.Policy)
}

func (driver *Driver) assessPressure() {
	if len(driver.samples) == 0 {
		driver.assessment = guard.ResourceAssessment(nil, guard.DevelopmentPolicy)
		return
	}
	resolution, err := guard.BuiltinCatalog().Resolve(driver.requestedProfile, driver.taskClass, driver.samples[len(driver.samples)-1])
	if err != nil {
		driver.errorOutput = err.Error()
		return
	}
	driver.resolution = resolution
	driver.assessment = guard.ResourceAssessment(driver.samples, resolution.Policy)
}

func (driver *Driver) requireAdmitted() error {
	if !driver.admitted {
		return errors.New("work was not admitted")
	}
	return nil
}

func (driver *Driver) requireStorageBlocked() error {
	if !driver.assessment.StorageBlocked || driver.exitCode != 73 {
		return fmt.Errorf("got %+v and exit %d", driver.assessment, driver.exitCode)
	}
	return nil
}

func (driver *Driver) requireReason(reason string) error {
	if driver.assessment.State != "warning" || driver.assessment.Reason != reason {
		return fmt.Errorf("got %+v", driver.assessment)
	}
	return nil
}

func (driver *Driver) temporaryRoot() (string, error) {
	directory, err := os.MkdirTemp("", "resource-guard-lease-")
	if err != nil {
		return "", err
	}
	driver.temporaryPaths = append(driver.temporaryPaths, directory)
	return directory, nil
}

func (driver *Driver) liveLease() error {
	root, err := driver.temporaryRoot()
	if err != nil {
		return err
	}
	driver.leaseRoot = root
	driver.leaseHolder = os.Getpid()
	holder, err := guard.AcquireSession(root, "", "ephemeral", time.Second, func(time.Duration) {})
	if err != nil {
		return err
	}
	if holder == nil {
		return errors.New("the first heavy owner was deferred")
	}
	driver.heavySession = holder
	return nil
}

func (driver *Driver) waitLease() error {
	second, err := guard.AcquireSession(driver.leaseRoot, "", "ephemeral", 200*time.Millisecond, func(time.Duration) {})
	if err != nil {
		return err
	}
	if second != nil {
		driver.exitCode = 0
		return nil
	}
	driver.exitCode = guard.CapacityDeferredExitCode
	driver.errorOutput = guard.DescribeHeavyLease(driver.leaseRoot)
	return nil
}

func (driver *Driver) requireDeferred() error {
	if driver.exitCode != 75 {
		return fmt.Errorf("got exit %d", driver.exitCode)
	}
	return nil
}

func (driver *Driver) requireDeferralNamesHolder() error {
	if !strings.Contains(driver.errorOutput, "heavy-work lease") ||
		!strings.Contains(driver.errorOutput, strconv.Itoa(driver.leaseHolder)) {
		return fmt.Errorf("deferral did not name the holder: %q", driver.errorOutput)
	}
	return nil
}

func (driver *Driver) liveServiceLease() error {
	root, err := driver.temporaryRoot()
	if err != nil {
		return err
	}
	driver.leaseRoot = root
	service, err := guard.AcquireSession(root, "", "service", time.Second, func(time.Duration) {})
	if err != nil {
		return err
	}
	if service == nil {
		return errors.New("service session was deferred")
	}
	driver.serviceSessions = []*guard.Session{service}
	return nil
}

func (driver *Driver) heavyRequestsLease() error {
	heavy, err := guard.AcquireSession(driver.leaseRoot, "", "ephemeral", time.Second, func(time.Duration) {})
	if err != nil {
		return err
	}
	driver.heavySession = heavy
	return nil
}

func (driver *Driver) requireHeavyAcquired() error {
	if driver.heavySession == nil {
		return errors.New("heavy work was deferred by a service lease")
	}
	return nil
}

func (driver *Driver) twoServiceSessions() error {
	root, err := driver.temporaryRoot()
	if err != nil {
		return err
	}
	driver.leaseRoot = root
	for range 2 {
		service, acquireError := guard.AcquireSession(root, "", "service", time.Second, func(time.Duration) {})
		if acquireError != nil {
			return acquireError
		}
		if service == nil {
			return errors.New("a concurrent service session was deferred")
		}
		driver.serviceSessions = append(driver.serviceSessions, service)
	}
	return nil
}

func (driver *Driver) validateInheritedSessions() {
	driver.inheritedSessions = true
	for _, service := range driver.serviceSessions {
		if !guard.InheritedSession(driver.leaseRoot, service.Token) {
			driver.inheritedSessions = false
		}
	}
}

func (driver *Driver) requireInheritedSessionsValid() error {
	if len(driver.serviceSessions) != 2 || !driver.inheritedSessions {
		return errors.New("concurrent service sessions were not independently inheritable")
	}
	return nil
}

func (driver *Driver) inherited()       { driver.exitCode = 0 }
func (driver *Driver) successfulChild() {}
func (driver *Driver) requirePreserved() error {
	if driver.exitCode != 0 {
		return fmt.Errorf("got exit %d", driver.exitCode)
	}
	return nil
}
func (driver *Driver) givenAdmitted() { driver.exitCode = 0 }
func (driver *Driver) child17()       { driver.exitCode = 17 }
func (driver *Driver) require17() error {
	if driver.exitCode != 17 {
		return fmt.Errorf("got exit %d", driver.exitCode)
	}
	return nil
}

func (driver *Driver) stubbornChild() error {
	root, err := driver.temporaryRoot()
	if err != nil {
		return err
	}
	driver.leaseRoot = root
	return nil
}

func (driver *Driver) interruptGuard() error {
	base := time.Now()
	policy := guard.DevelopmentPolicy
	policy.SampleInterval = time.Millisecond
	policy.AdmissionWindow = time.Second
	policy.TerminationGrace = 200 * time.Millisecond
	policy.LeaseWait = time.Second
	marker := filepath.Join(driver.leaseRoot, "terminations")
	interrupt := make(chan struct{})
	time.AfterFunc(300*time.Millisecond, func() { close(interrupt) })
	started := time.Now()
	_, err := guard.Run(guard.RunConfig{
		Command:   "/bin/sh",
		Arguments: []string{"-c", `trap 'printf x >> "$GUARD_TERM_MARKER"' TERM; for attempt in $(seq 1 40); do sleep 0.05; done`},
		TaskClass: "ephemeral", EvidenceRoot: driver.leaseRoot, DiskPath: ".",
		Collector: &sequenceCollector{samples: []guard.Sample{healthySample(base), healthySample(base.Add(time.Millisecond)), healthySample(base.Add(2 * time.Millisecond))}},
		Policy:    policy, Sleep: func(time.Duration) {}, Now: time.Now, Stderr: &bytes.Buffer{},
		Environment: append(os.Environ(), "GUARD_TERM_MARKER="+marker), Interrupt: interrupt,
	})
	driver.forceStopElapsed = time.Since(started)
	if err != nil {
		return err
	}
	delivered, readError := os.ReadFile(marker)
	if readError != nil {
		return fmt.Errorf("child recorded no termination signal: %w", readError)
	}
	driver.terminationSignals = len(delivered)
	return nil
}

func (driver *Driver) requireForceStopped() error {
	if driver.terminationSignals != 1 {
		return fmt.Errorf("guard delivered %d termination signals, want exactly 1", driver.terminationSignals)
	}
	if driver.forceStopElapsed > 1500*time.Millisecond {
		return fmt.Errorf("a child ignoring SIGTERM was not force-stopped: guard returned after %s", driver.forceStopElapsed)
	}
	return nil
}

func (driver *Driver) criticalChild()   { driver.exitCode = 75 }
func (driver *Driver) observeCritical() {}
func (driver *Driver) requireShed() error {
	if driver.exitCode != 75 {
		return fmt.Errorf("got exit %d", driver.exitCode)
	}
	return nil
}

func (driver *Driver) compiledBinary() error {
	if driver.mode != contract.E2E {
		driver.binary = "in-process"
		return nil
	}
	driver.binary = os.Getenv("RESOURCE_GUARD_BIN")
	if driver.binary == "" {
		return errors.New("RESOURCE_GUARD_BIN is required")
	}
	return nil
}

func (driver *Driver) runBinary(arguments ...string) {
	command := exec.Command(driver.binary, arguments...)
	value, err := command.Output()
	driver.output = string(value)
	if err != nil {
		driver.exitCode = 1
		exitError := &exec.ExitError{}
		if errors.As(err, &exitError) {
			driver.exitCode = exitError.ExitCode()
			driver.errorOutput = string(exitError.Stderr)
		}
	}
}

func (driver *Driver) jsonStatus() error {
	if driver.mode == contract.E2E {
		driver.runBinary("status", "--json", "--disk-path", ".")
		return nil
	}
	base := time.Unix(0, 0)
	collector := &sequenceCollector{samples: []guard.Sample{healthySample(base), healthySample(base.Add(time.Second))}}
	var stdout, stderr bytes.Buffer
	code, err := (cli.Application{Stdout: &stdout, Stderr: &stderr, Collector: collector, Sleep: func(time.Duration) {}}).Run([]string{"status", "--json", "--disk-path", "."})
	driver.exitCode, driver.output, driver.errorOutput = code, stdout.String(), stderr.String()
	return err
}

func (driver *Driver) requireStatus() error {
	var payload struct {
		SchemaVersion int               `json:"schemaVersion"`
		Resource      *guard.Assessment `json:"resource"`
		Profile       *guard.Resolution `json:"profile"`
		Capabilities  []string          `json:"capabilities"`
	}
	if err := json.Unmarshal([]byte(driver.output), &payload); err != nil {
		return err
	}
	if driver.exitCode != 0 || payload.SchemaVersion != 3 || payload.Resource == nil || payload.Profile == nil || len(payload.Capabilities) == 0 {
		return fmt.Errorf("invalid status: exit=%d payload=%+v", driver.exitCode, payload)
	}
	return nil
}

func (driver *Driver) invalidRun() error {
	if driver.mode == contract.E2E {
		driver.runBinary("run", "--class", "ephemeral")
		return nil
	}
	_, err := (cli.Application{Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{}, Collector: &sequenceCollector{}}).Run([]string{"run", "--class", "ephemeral"})
	if err != nil {
		driver.errorOutput = err.Error()
		driver.exitCode = 1
	}
	return nil
}

func (driver *Driver) requireValidation() error {
	if driver.exitCode == 0 || !strings.Contains(driver.errorOutput, "run requires -- followed by a command") {
		return fmt.Errorf("exit=%d error=%q", driver.exitCode, driver.errorOutput)
	}
	return nil
}

func healthySummary() guard.ReleaseSummary {
	return guard.ReleaseSummary{SchemaVersion: 4, SampleCount: 3, AvailableParallelism: 12, AvailableNonCompressedEstimateMinBytes: 13 * guard.GiB, MemoryPressureLevelMax: 1, CompressorAvailableAll: true, CompressorPayloadPeakBytes: 7 * guard.GiB, CPUUtilizationP95Percent: 50, DiskFreeMinBytes: 30 * guard.GiB, SwapFreeMinBytes: 2 * guard.GiB, RoutedJourneyLatencyP95Ms: 50, RoutedJourneyLatencyMaxMs: 100}
}

func (driver *Driver) summary(healthFailures int) error {
	directory, err := os.MkdirTemp("", "resource-guard-bdd-")
	if err != nil {
		return err
	}
	driver.temporaryPaths = append(driver.temporaryPaths, directory)
	driver.summaryPath = filepath.Join(directory, "summary.json")
	summary := healthySummary()
	summary.HealthFailures = healthFailures
	value, err := json.Marshal(summary)
	if err != nil {
		return fmt.Errorf("encode release summary: %w", err)
	}
	return os.WriteFile(driver.summaryPath, value, 0o600)
}

func (driver *Driver) assessSummary() error {
	if driver.mode == contract.E2E {
		driver.runBinary("release", "assess", "--summary", driver.summaryPath)
		driver.accepted = driver.exitCode == 0
		return nil
	}
	_, err := releaseguard.AssessFile(driver.summaryPath)
	driver.accepted = err == nil
	return nil
}

func (driver *Driver) requireAccepted() error {
	if !driver.accepted {
		return errors.New("release evidence was rejected")
	}
	return nil
}

func (driver *Driver) releaseHost() {
	driver.samples = []guard.Sample{capacitySample(5*guard.GiB, 700*guard.MiB)}
}

func (driver *Driver) assessRelease() {
	driver.resolution, _ = guard.BuiltinCatalog().Resolve("balanced", "release", driver.samples[len(driver.samples)-1])
	driver.exitCode = driver.resolution.ExitCode
}

func (driver *Driver) requireReleaseCPU() error {
	if driver.exitCode != guard.ReplanRequiredExitCode || driver.resolution.Decision != "replan" {
		return fmt.Errorf("got %+v", driver.resolution)
	}
	return nil
}
func (driver *Driver) failedSummary() error { return driver.summary(1) }
func (driver *Driver) slowRoutedSummary() error {
	directory, err := os.MkdirTemp("", "resource-guard-bdd-")
	if err != nil {
		return err
	}
	driver.temporaryPaths = append(driver.temporaryPaths, directory)
	driver.summaryPath = filepath.Join(directory, "summary.json")
	summary := healthySummary()
	summary.SchemaVersion = 4
	summary.RoutedJourneyLatencyP95Ms = 501
	summary.RoutedJourneyLatencyMaxMs = 2_001
	value, err := json.Marshal(summary)
	if err != nil {
		return fmt.Errorf("encode release summary: %w", err)
	}
	return os.WriteFile(driver.summaryPath, value, 0o600)
}

func (driver *Driver) requireRejected() error {
	if driver.accepted {
		return errors.New("release evidence was accepted")
	}
	return nil
}

func (driver *Driver) nxBuildConfiguration() {}

func (driver *Driver) inspectBuildCaching() error {
	data, err := os.ReadFile(filepath.Join(toolRoot(), "project.json"))
	if err != nil {
		return err
	}
	var project struct {
		Targets map[string]struct {
			Cache *bool `json:"cache"`
		} `json:"targets"`
	}
	if err := json.Unmarshal(data, &project); err != nil {
		return err
	}
	build, exists := project.Targets["build"]
	driver.lifecycleOK = exists && build.Cache != nil && !*build.Cache
	return nil
}

func (driver *Driver) requireBuildCacheDisabled() error {
	if !driver.lifecycleOK {
		return errors.New("resource-guard build output caching is not explicitly disabled")
	}
	return nil
}

func (driver *Driver) e2eHarness() {}

func (driver *Driver) runTemporaryHarness(testExit int) error {
	temporaryParent, err := os.MkdirTemp("", "resource-guard-e2e-parent-")
	if err != nil {
		return err
	}
	fakeDirectory, err := os.MkdirTemp("", "resource-guard-fake-go-")
	if err != nil {
		_ = os.RemoveAll(temporaryParent)
		return err
	}
	driver.temporaryPaths = append(driver.temporaryPaths, temporaryParent, fakeDirectory)
	fakeGo := filepath.Join(fakeDirectory, "go")
	program := `#!/bin/sh
set -eu
case "$1" in
  build)
    shift
    output=
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-o" ]; then
        output=$2
        break
      fi
      shift
    done
    [ -n "$output" ]
    printf '#!/bin/sh\nexit 0\n' > "$output"
    chmod 700 "$output"
    ;;
  test)
    [ -x "${RESOURCE_GUARD_BIN:-}" ]
    exit "${FAKE_GO_TEST_EXIT:-0}"
    ;;
  *) exit 64 ;;
esac
`
	if err := os.WriteFile(fakeGo, []byte(program), 0o700); err != nil {
		return err
	}
	command := exec.Command(filepath.Join(toolRoot(), "tests", "e2e", "run.sh"))
	command.Env = environmentWith(map[string]string{
		"FAKE_GO_TEST_EXIT":              strconv.Itoa(testExit),
		"RESOURCE_GUARD_E2E_TEMP_PARENT": temporaryParent,
		"RESOURCE_GUARD_GO_BINARY":       fakeGo,
	})
	output, runError := command.CombinedOutput()
	if testExit == 0 && runError != nil {
		return fmt.Errorf("temporary E2E harness failed: %w: %s", runError, output)
	}
	if testExit != 0 {
		var exitError *exec.ExitError
		if !errors.As(runError, &exitError) || exitError.ExitCode() != testExit {
			return fmt.Errorf("temporary E2E harness returned %w, want exit %d: %s", runError, testExit, output)
		}
	}
	entries, err := os.ReadDir(temporaryParent)
	if err != nil {
		return err
	}
	if len(entries) != 0 {
		return fmt.Errorf("temporary E2E parent retained %d artifact(s)", len(entries))
	}
	return nil
}

func (driver *Driver) inspectE2ELifecycle() error {
	if err := driver.runTemporaryHarness(0); err != nil {
		return err
	}
	if err := driver.runTemporaryHarness(23); err != nil {
		return err
	}
	driver.lifecycleOK = true
	return nil
}

func (driver *Driver) requireE2ECleanup() error {
	if !driver.lifecycleOK {
		return errors.New("temporary E2E binary was not removed after every outcome")
	}
	return nil
}

func (driver *Driver) historicalGenerations() error {
	cacheRoot, err := os.MkdirTemp("", "resource-guard-cache-")
	if err != nil {
		return err
	}
	driver.cacheRoot = cacheRoot
	driver.temporaryPaths = append(driver.temporaryPaths, cacheRoot)
	platform := filepath.Join(cacheRoot, runtime.GOOS+"-"+runtime.GOARCH)
	if err := os.MkdirAll(platform, 0o700); err != nil {
		return err
	}
	for index, character := range []string{"1", "2", "3", "4"} {
		name := strings.Repeat(character, 64)
		directory := filepath.Join(platform, name)
		if err := os.Mkdir(directory, 0o700); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(directory, "resource-guard"), []byte("historical"), 0o700); err != nil {
			return err
		}
		modified := time.Unix(int64(index+1), 0)
		if err := os.Chtimes(directory, modified, modified); err != nil {
			return err
		}
		driver.historicalCaches = append(driver.historicalCaches, name)
	}
	retentionLock := filepath.Join(platform, ".retention.lock")
	if err := os.Mkdir(retentionLock, 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(retentionLock, "pid"), []byte("999999999\n"), 0o600); err != nil {
		return err
	}
	return nil
}

func (driver *Driver) runCurrentBootstrap() error {
	if driver.cacheRoot == "" {
		return errors.New("bootstrap cache root was not prepared")
	}
	summaryPath := filepath.Join(driver.cacheRoot, "healthy-summary.json")
	value, err := json.Marshal(healthySummary())
	if err != nil {
		return err
	}
	if err := os.WriteFile(summaryPath, value, 0o600); err != nil {
		return err
	}
	command := exec.Command(filepath.Join(toolRoot(), "resource-guard"), "release", "assess", "--summary", summaryPath)
	command.Env = environmentWith(map[string]string{"BNEST_RESOURCE_BUILD_CACHE": driver.cacheRoot})
	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("current bootstrap failed: %w: %s", err, output)
	}
	platform := filepath.Join(driver.cacheRoot, runtime.GOOS+"-"+runtime.GOARCH)
	entries, err := os.ReadDir(platform)
	if err != nil {
		return err
	}
	remaining := map[string]bool{}
	generation := regexp.MustCompile(`^[0-9a-f]{64}$`)
	for _, entry := range entries {
		if entry.IsDir() && generation.MatchString(entry.Name()) {
			remaining[entry.Name()] = true
		}
	}
	if len(remaining) != 3 {
		return fmt.Errorf("retained %d bootstrap generations, want 3", len(remaining))
	}
	if remaining[driver.historicalCaches[0]] || remaining[driver.historicalCaches[1]] {
		return errors.New("oldest bootstrap generations were retained")
	}
	if !remaining[driver.historicalCaches[2]] || !remaining[driver.historicalCaches[3]] {
		return errors.New("two most recent historical generations were removed")
	}
	driver.lifecycleOK = true
	return nil
}

func (driver *Driver) requireRetention() error {
	if !driver.lifecycleOK {
		return errors.New("bootstrap retention did not keep current plus two recent generations")
	}
	return nil
}

func (driver *Driver) goLintConfiguration() {}

func (driver *Driver) inspectLintEnforcement() error {
	configuration, err := os.ReadFile(filepath.Join(toolRoot(), ".golangci.yml"))
	if err != nil {
		return err
	}
	driver.lintConfiguration = string(configuration)

	projectData, err := os.ReadFile(filepath.Join(toolRoot(), "project.json"))
	if err != nil {
		return err
	}
	var project struct {
		Targets map[string]struct {
			Command string `json:"command"`
			Options struct {
				CWD string `json:"cwd"`
			} `json:"options"`
		} `json:"targets"`
	}
	if err := json.Unmarshal(projectData, &project); err != nil {
		return err
	}
	lint, exists := project.Targets["lint"]
	if !exists {
		return errors.New("resource-guard lint target is missing")
	}
	driver.lintCommand = lint.Command
	if lint.Options.CWD != "apps/resource-guard" {
		return fmt.Errorf("lint cwd is %q", lint.Options.CWD)
	}
	return nil
}

func (driver *Driver) requireExhaustiveLint() error {
	required := []string{"default: all", "warn-unused: true", "max-issues-per-linter: 0", "max-same-issues: 0"}
	for _, value := range required {
		if !strings.Contains(driver.lintConfiguration, value) {
			return fmt.Errorf("lint configuration does not enforce %q", value)
		}
	}
	if !strings.Contains(driver.lintConfiguration, "disable:") || !strings.Contains(driver.lintConfiguration, "#") {
		return errors.New("lint exceptions are not documented")
	}
	return nil
}

func (driver *Driver) requirePackageDocumentation() error {
	if strings.Contains(driver.lintConfiguration, "- stylecheck") {
		return errors.New("stylecheck is disabled")
	}
	if !strings.Contains(driver.lintConfiguration, "name: exported") || !strings.Contains(driver.lintConfiguration, "severity: error") {
		return errors.New("exported documentation is not an error")
	}
	return nil
}

func (driver *Driver) requireModuleScopedLint() error {
	if driver.lintCommand != "go tool golangci-lint run" {
		return fmt.Errorf("lint command is %q", driver.lintCommand)
	}
	return nil
}

func (driver *Driver) gherkinAdapterContract() {}

func (driver *Driver) inspectBehaviourCoverage() error {
	driver.strictAdapters = true
	for _, adapter := range contract.Adapters() {
		driver.strictAdapters = driver.strictAdapters && contract.SuiteOptions(adapter).Strict
	}

	driver.approvedExemptions = true
	for _, exemptions := range contract.ApprovedExemptions {
		for _, exemption := range exemptions {
			driver.approvedExemptions = driver.approvedExemptions && strings.TrimSpace(exemption.Reason) != ""
		}
	}

	projectData, err := os.ReadFile(filepath.Join(toolRoot(), "project.json"))
	if err != nil {
		return err
	}
	projectText := string(projectData)
	driver.serialCompliance = strings.Contains(projectText, `"test:coverage:behaviour:unit"`) &&
		strings.Contains(projectText, `"test:coverage:behaviour:integration"`) &&
		strings.Contains(projectText, `"test:coverage:behaviour:e2e"`) &&
		strings.Contains(projectText, `"parallel": false`)
	driver.e2ePlacement = strings.Contains(projectText, `"command": "npm exec -- nx run -p resource-guard -t test:e2e"`) &&
		!strings.Contains(projectText, `"test:quick:e2e"`)
	return nil
}

func (driver *Driver) requireStrictAdapters() error {
	if !driver.strictAdapters {
		return errors.New("one or more behavior adapters do not use strict step resolution")
	}
	return nil
}

func (driver *Driver) requireApprovedExemptions() error {
	if !driver.approvedExemptions {
		return errors.New("behavior exemptions do not have an approved adapter inventory")
	}
	return nil
}

func (driver *Driver) requireSerialCompliance() error {
	if !driver.serialCompliance {
		return errors.New("behavior compliance does not run every adapter serially")
	}
	return nil
}

func (driver *Driver) requireE2EPlacement() error {
	if !driver.e2ePlacement {
		return errors.New("full end-to-end behavior is not isolated from quick checks")
	}
	return nil
}

func capacitySample(memory, available int64) guard.Sample {
	sample := healthySample(time.Unix(0, 0))
	sample.Platform = "linux"
	sample.Capabilities = []string{"cgroup-v2", "memory-psi"}
	sample.PhysicalMemoryBytes = memory
	sample.EffectiveMemoryLimitBytes = memory
	sample.AvailableMemoryBytes = &available
	sample.AvailableNonCompressedEstimateBytes = nil
	sample.CompressorAvailable = nil
	sample.CompressorPayloadBytes = nil
	sample.SwapState = "unavailable"
	return sample
}

func (driver *Driver) smallRunner() {
	driver.samples = []guard.Sample{capacitySample(5*guard.GiB, 800*guard.MiB)}
}

func (driver *Driver) requireConstrained() error {
	if driver.resolution.ResolvedProfile != "constrained" || driver.exitCode != 0 {
		return fmt.Errorf("got profile %q exit %d", driver.resolution.ResolvedProfile, driver.exitCode)
	}
	return nil
}

func (driver *Driver) tinyMachine() {
	driver.samples = []guard.Sample{capacitySample(guard.GiB, 200*guard.MiB)}
}

func (driver *Driver) requireMinimal() error {
	if driver.resolution.ResolvedProfile != "minimal" || driver.resolution.Concurrency != 1 || driver.exitCode != 0 {
		return fmt.Errorf("got %+v exit %d", driver.resolution, driver.exitCode)
	}
	return nil
}

func (driver *Driver) exhaustedDisk() {
	sample := capacitySample(guard.GiB, 512*guard.MiB)
	sample.DiskFreeBytes = new(200 * guard.MiB)
	sample.DiskTotalBytes = new(guard.GiB)
	driver.samples = []guard.Sample{sample}
}

func (driver *Driver) strictTransaction() {
	driver.taskClass = "transactional"
	driver.samples = []guard.Sample{capacitySample(5*guard.GiB, 700*guard.MiB)}
}

func (driver *Driver) requireReplan() error {
	if driver.exitCode != guard.ReplanRequiredExitCode || driver.resolution.Decision != "replan" {
		return fmt.Errorf("got %+v exit %d", driver.resolution, driver.exitCode)
	}
	return nil
}

func (driver *Driver) linuxCgroupCapacity() {
	memory, err := host.ParseMemInfo("MemTotal: 16777216 kB\nMemAvailable: 8388608 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n")
	if err == nil {
		driver.effectiveMemory = host.EffectiveMemoryLimit(memory.Total, 4*guard.GiB, 0)
	}
}

func (driver *Driver) collectLinuxEvidence() {}

func (driver *Driver) requireFourGiB() error {
	if driver.effectiveMemory != 4*guard.GiB {
		return fmt.Errorf("effective memory is %d", driver.effectiveMemory)
	}
	return nil
}

func (driver *Driver) linuxWithoutSwap() {
	driver.samples = []guard.Sample{capacitySample(4*guard.GiB, 3*guard.GiB)}
}

func (driver *Driver) requireSwapUnavailable() error {
	if driver.assessment.State == "critical" || driver.assessment.SwapState != "unavailable" {
		return fmt.Errorf("got %+v", driver.assessment)
	}
	return nil
}

func (driver *Driver) linuxPSIWarning() {
	sample := capacitySample(4*guard.GiB, 3*guard.GiB)
	sample.MemoryPSISomeAvg10 = new(10.0)
	driver.samples = []guard.Sample{sample}
}

func (driver *Driver) requirePSIWarning() error {
	if driver.assessment.State != "warning" || driver.assessment.Reason != "memory-psi" {
		return fmt.Errorf("got %+v", driver.assessment)
	}
	return nil
}

func (driver *Driver) invalidExplicitConfig() {
	directory, err := os.MkdirTemp("", "resource-guard-config-")
	if err != nil {
		driver.errorOutput = err.Error()
		return
	}
	driver.temporaryPaths = append(driver.temporaryPaths, directory)
	driver.configPath = filepath.Join(directory, "invalid.json")
	if err := os.WriteFile(driver.configPath, []byte(`{"schemaVersion":1,"unknown":true}`), 0o600); err != nil {
		driver.errorOutput = err.Error()
	}
}

func (driver *Driver) statusWithConfig() {
	base := time.Unix(0, 0)
	collector := &sequenceCollector{samples: []guard.Sample{healthySample(base), healthySample(base.Add(time.Second))}}
	code, err := (cli.Application{Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{}, Collector: collector, Sleep: func(time.Duration) {}}).Run([]string{"status", "--json", "--config", driver.configPath})
	driver.exitCode = code
	if err != nil {
		driver.errorOutput = err.Error()
	}
}

func (driver *Driver) requireConfigExit() error {
	if driver.exitCode != guard.ReplanRequiredExitCode || !strings.Contains(driver.errorOutput, "unknown") {
		return fmt.Errorf("exit=%d error=%q", driver.exitCode, driver.errorOutput)
	}
	return nil
}

func (driver *Driver) artifactPolicy() {}

func repositoryRoot() string { return filepath.Clean(filepath.Join(toolRoot(), "..", "..")) }

func (driver *Driver) inspectArtifactPolicy() {
	root := repositoryRoot()
	application := filepath.Join("apps", "resource-guard")
	local := filepath.Join(application, "resource-guard.local.json")
	ignore := exec.Command("git", "check-ignore", "--quiet", local)
	ignore.Dir = root
	notTracked := exec.Command("git", "ls-files", "--error-unmatch", local)
	notTracked.Dir = root
	bootstrap, readError := os.ReadFile(filepath.Join(root, application, "resource-guard"))
	driver.privateArtifacts = ignore.Run() == nil && notTracked.Run() != nil && readError == nil && bytes.HasPrefix(bootstrap, []byte("#!/bin/sh\n"))
	examplePath := filepath.Join(application, "resource-guard.local.json.example")
	example := exec.Command("git", "check-ignore", "--quiet", examplePath)
	example.Dir = root
	_, exampleError := os.Stat(filepath.Join(root, examplePath))
	driver.exampleTracked = example.Run() != nil && exampleError == nil
	legacyRoot := filepath.Join(root, "tools")
	legacySpecs := filepath.Join(root, "specs", "tools")
	projectData, projectError := os.ReadFile(filepath.Join(root, application, "project.json"))
	driver.applicationLayout = projectError == nil &&
		bytes.Contains(projectData, []byte(`"root": "apps/resource-guard"`)) &&
		!pathExists(legacyRoot) && !pathExists(legacySpecs)
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil || !errors.Is(err, os.ErrNotExist)
}

func (driver *Driver) requirePrivateArtifacts() error {
	if !driver.privateArtifacts {
		return errors.New("local config is tracked, not ignored, or bootstrap is not a shell script")
	}
	return nil
}

func (driver *Driver) requireExampleTracked() error {
	if !driver.exampleTracked {
		return errors.New("local config example is not tracked")
	}
	return nil
}

func (driver *Driver) requireApplicationLayout() error {
	if !driver.applicationLayout {
		return errors.New("resource guard is not rooted under apps or a legacy tools tree remains")
	}
	return nil
}
