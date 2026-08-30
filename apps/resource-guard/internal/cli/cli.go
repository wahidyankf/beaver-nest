package cli

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	resourceconfig "github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/config"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/guard"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/host"
	releaseguard "github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/release"
)

const unavailableValue = "unavailable"

// Application supplies the command's injectable host and I/O dependencies.
type Application struct {
	Stdout, Stderr io.Writer
	Environment    []string
	Collector      guard.Collector
	Sleep          func(time.Duration)
	Now            func() time.Time
}

func environmentMap(environment []string) map[string]string {
	result := map[string]string{}
	for _, entry := range environment {
		for index := range entry {
			if entry[index] == '=' {
				result[entry[:index]] = entry[index+1:]
				break
			}
		}
	}
	return result
}

func (application Application) defaults() Application {
	if application.Stdout == nil {
		application.Stdout = os.Stdout
	}
	if application.Stderr == nil {
		application.Stderr = os.Stderr
	}
	if application.Environment == nil {
		application.Environment = os.Environ()
	}
	if application.Collector == nil {
		application.Collector = host.SystemCollector{}
	}
	if application.Sleep == nil {
		application.Sleep = time.Sleep
	}
	if application.Now == nil {
		application.Now = time.Now
	}
	return application
}

// Run executes one resource-guard command and returns its process exit code.
func (application Application) Run(arguments []string) (int, error) {
	application = application.defaults()
	if len(arguments) == 0 {
		return 1, errors.New("expected status, monitor, run, or release")
	}
	switch arguments[0] {
	case "status":
		return application.status(arguments[1:])
	case "monitor":
		return application.monitor(arguments[1:])
	case "run":
		return application.run(arguments[1:])
	case "release":
		return application.release(arguments[1:])
	default:
		return 1, errors.New("expected status, monitor, run, or release")
	}
}

func flagSet(name string, output io.Writer) *flag.FlagSet {
	set := flag.NewFlagSet(name, flag.ContinueOnError)
	set.SetOutput(output)
	return set
}

func (application Application) loadConfig(path string) (resourceconfig.Result, error) {
	environment := environmentMap(application.Environment)
	resolvedPath, explicit := resourceconfig.Path(path, environment)
	return resourceconfig.Load(resolvedPath, explicit)
}

func configFlags(flags *flag.FlagSet) (*string, *string) {
	return flags.String("config", "", "strict local JSON configuration"), flags.String("profile", "", "requested resource profile")
}

func withAssessmentDecision(resolution guard.Resolution, assessment guard.Assessment) guard.Resolution {
	if resolution.ExitCode != 0 {
		return resolution
	}
	if assessment.StorageBlocked {
		resolution.Decision, resolution.ExitCode = "cleanup", guard.StorageBlockedExitCode
	} else if assessment.State != "normal" {
		resolution.Decision, resolution.ExitCode, resolution.Retryable = "wait", guard.CapacityDeferredExitCode, true
	}
	return resolution
}

func (application Application) status(arguments []string) (int, error) {
	flags := flagSet("status", application.Stderr)
	jsonOutput := flags.Bool("json", false, "emit JSON")
	diskPath := flags.String("disk-path", ".", "path whose free space is measured")
	configPath, requestedProfile := configFlags(flags)
	if err := flags.Parse(arguments); err != nil {
		return 1, err
	}
	if flags.NArg() != 0 {
		return 1, errors.New("status accepts only flags")
	}
	configuration, configError := application.loadConfig(*configPath)
	if configError != nil {
		return guard.ReplanRequiredExitCode, fmt.Errorf("resource configuration: %w", configError)
	}
	first, err := application.Collector.Collect(nil, *diskPath)
	if err != nil {
		return 1, err
	}
	application.Sleep(time.Second)
	second, err := application.Collector.Collect(first.CPUState, *diskPath)
	if err != nil {
		return 1, err
	}
	resolution, resolveError := configuration.Catalog.Resolve(*requestedProfile, "ephemeral", second.Sample)
	if resolveError != nil {
		return guard.ReplanRequiredExitCode, resolveError
	}
	assessment := guard.ResourceAssessment([]guard.Sample{first.Sample, second.Sample}, resolution.Policy)
	resolution = withAssessmentDecision(resolution, assessment)
	if *jsonOutput {
		payload := struct {
			guard.Sample

			Resource   guard.Assessment `json:"resource"`
			Profile    guard.Resolution `json:"profile"`
			ConfigHash string           `json:"configHash,omitempty"`
		}{second.Sample, assessment, resolution, configuration.Hash}
		encoded, marshalError := json.Marshal(payload)
		if marshalError != nil {
			return 1, fmt.Errorf("encode status JSON: %w", marshalError)
		}
		_, err = fmt.Fprintln(application.Stdout, string(encoded))
		return 0, err
	}
	available, disk, cpu := unavailableValue, unavailableValue, unavailableValue
	availableBytes := second.Sample.AvailableMemoryBytes
	if availableBytes == nil {
		availableBytes = second.Sample.AvailableNonCompressedEstimateBytes
	}
	if availableBytes != nil {
		available = fmt.Sprintf("%.2f", float64(*availableBytes)/float64(guard.GiB))
	}
	if second.Sample.DiskFreeBytes != nil {
		disk = fmt.Sprintf("%.2f", float64(*second.Sample.DiskFreeBytes)/float64(guard.GiB))
	}
	if second.Sample.CPUUtilizationPercent != nil {
		cpu = fmt.Sprintf("%.1f%%", *second.Sample.CPUUtilizationPercent)
	}
	_, err = fmt.Fprintf(application.Stdout, "state=%s reason=%s profile=%s concurrency=%d swap=%s availableGiB=%s diskFreeGiB=%s cpu=%s\n", assessment.State, assessment.Reason, resolution.ResolvedProfile, resolution.Concurrency, second.Sample.SwapState, available, disk, cpu)
	return 0, err
}

func (application Application) monitor(arguments []string) (int, error) {
	flags := flagSet("monitor", application.Stderr)
	diskPath := flags.String("disk-path", ".", "path whose free space is measured")
	interval := flags.Duration("interval", time.Second, "sample interval")
	configPath, requestedProfile := configFlags(flags)
	if err := flags.Parse(arguments); err != nil {
		return 1, err
	}
	if *interval <= 0 {
		return 1, errors.New("interval must be positive")
	}
	configuration, configError := application.loadConfig(*configPath)
	if configError != nil {
		return guard.ReplanRequiredExitCode, fmt.Errorf("resource configuration: %w", configError)
	}
	var previous guard.CPUState
	samples := []guard.Sample{}
	prior := ""
	observe := func() error {
		reading, err := application.Collector.Collect(previous, *diskPath)
		if err != nil {
			return err
		}
		previous = reading.CPUState
		samples = append(samples, reading.Sample)
		if len(samples) > 17 {
			samples = samples[len(samples)-17:]
		}
		resolution, resolveError := configuration.Catalog.Resolve(*requestedProfile, "ephemeral", reading.Sample)
		if resolveError != nil {
			return resolveError
		}
		assessment := guard.ResourceAssessment(samples, resolution.Policy)
		state := assessment.State + ":" + assessment.Reason + ":" + resolution.ResolvedProfile
		if state != prior {
			if _, writeError := fmt.Fprintf(application.Stdout, "%s state=%s reason=%s profile=%s swap=%s\n", reading.Sample.MeasuredAt, assessment.State, assessment.Reason, resolution.ResolvedProfile, reading.Sample.SwapState); writeError != nil {
				return writeError
			}
			prior = state
		}
		return nil
	}
	if err := observe(); err != nil {
		return 1, err
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(signals)
	ticker := time.NewTicker(*interval)
	defer ticker.Stop()
	for {
		select {
		case <-signals:
			return 0, nil
		case <-ticker.C:
			if err := observe(); err != nil {
				return 1, err
			}
		}
	}
}

func splitRun(arguments []string) ([]string, []string, error) {
	for index, argument := range arguments {
		if argument == "--" {
			if index+1 >= len(arguments) {
				return nil, nil, errors.New("run requires -- followed by a command")
			}
			return arguments[:index], arguments[index+1:], nil
		}
	}
	return nil, nil, errors.New("run requires -- followed by a command")
}

func (application Application) run(arguments []string) (int, error) {
	flagArguments, command, err := splitRun(arguments)
	if err != nil {
		return 1, err
	}
	flags := flagSet("run", application.Stderr)
	class := flags.String("class", "ephemeral", "task class")
	cwd := flags.String("cwd", "", "child working directory")
	diskPath := flags.String("disk-path", "", "path whose free space is measured")
	leasePort := flags.Int("lease-port", 0, "service port to lease")
	leaseOwner := flags.String("lease-owner", "", "service port owner")
	leaseMinimum := flags.Int("lease-min", 0, "minimum allowed leased port")
	leaseMaximum := flags.Int("lease-max", 0, "maximum allowed leased port")
	configPath, requestedProfile := configFlags(flags)
	if err = flags.Parse(flagArguments); err != nil {
		return 1, err
	}
	if flags.NArg() != 0 {
		return 1, errors.New("unknown run arguments")
	}
	if *cwd != "" {
		absolute, absoluteError := filepath.Abs(*cwd)
		if absoluteError != nil {
			return 1, absoluteError
		}
		*cwd = absolute
	}
	root := host.DefaultEvidenceRoot(environmentMap(application.Environment))
	if root == "" {
		return 1, errors.New("resource evidence root is unavailable")
	}
	configuration, configError := application.loadConfig(*configPath)
	if configError != nil {
		return guard.ReplanRequiredExitCode, fmt.Errorf("resource configuration: %w", configError)
	}
	probeDiskPath := *diskPath
	if probeDiskPath == "" {
		probeDiskPath = *cwd
	}
	if probeDiskPath == "" {
		probeDiskPath = "."
	}
	probe, collectError := application.Collector.Collect(nil, probeDiskPath)
	if collectError != nil {
		return 1, collectError
	}
	resolution, resolveError := configuration.Catalog.Resolve(*requestedProfile, *class, probe.Sample)
	if resolveError != nil {
		return guard.ReplanRequiredExitCode, resolveError
	}
	if resolution.ExitCode != 0 {
		_, _ = fmt.Fprintf(application.Stderr, "Resource guard decision=%s requested=%s resolved=%s.\n", resolution.Decision, resolution.RequestedProfile, resolution.ResolvedProfile)
		return resolution.ExitCode, nil
	}
	return guard.Run(guard.RunConfig{Command: command[0], Arguments: command[1:], TaskClass: *class, WorkingDirectory: *cwd, Environment: application.Environment, EvidenceRoot: root, DiskPath: *diskPath, LeasePort: *leasePort, LeaseOwner: *leaseOwner, LeaseMinimum: *leaseMinimum, LeaseMaximum: *leaseMaximum, Collector: application.Collector, Policy: resolution.Policy, Resolution: resolution, ConfigHash: configuration.Hash, Sleep: application.Sleep, Now: application.Now, Stderr: application.Stderr})
}

func (application Application) release(arguments []string) (int, error) { //nolint:gocognit // Each release subcommand owns distinct strict validation and exit semantics.
	if len(arguments) == 0 {
		return 1, errors.New("release requires check, monitor, or assess")
	}
	switch arguments[0] {
	case "check":
		flags := flagSet("release check", application.Stderr)
		diskPath := flags.String("disk-path", ".", "deployment path")
		configPath, requestedProfile := configFlags(flags)
		if err := flags.Parse(arguments[1:]); err != nil {
			return 1, err
		}
		configuration, configError := application.loadConfig(*configPath)
		if configError != nil {
			return guard.ReplanRequiredExitCode, fmt.Errorf("resource configuration: %w", configError)
		}
		probe, collectError := application.Collector.Collect(nil, *diskPath)
		if collectError != nil {
			return 1, collectError
		}
		resolution, resolveError := configuration.Catalog.Resolve(*requestedProfile, "release", probe.Sample)
		if resolveError != nil {
			return guard.ReplanRequiredExitCode, resolveError
		}
		if resolution.ExitCode != 0 {
			return resolution.ExitCode, nil
		}
		if err := releaseguard.CheckWithPolicy(application.Collector, *diskPath, application.Sleep, resolution.Policy); err != nil {
			_, _ = fmt.Fprintln(application.Stderr, err)
			return guard.CapacityDeferredExitCode, nil
		}
		return 0, nil
	case "assess":
		flags := flagSet("release assess", application.Stderr)
		summaryPath := flags.String("summary", "", "summary JSON path")
		configPath, _ := configFlags(flags)
		if err := flags.Parse(arguments[1:]); err != nil {
			return 1, err
		}
		if *summaryPath == "" {
			return 1, errors.New("--summary is required")
		}
		if _, configError := application.loadConfig(*configPath); configError != nil {
			return guard.ReplanRequiredExitCode, fmt.Errorf("resource configuration: %w", configError)
		}
		summary, err := releaseguard.AssessFile(*summaryPath)
		accepted := err == nil
		encoded, marshalError := json.Marshal(map[string]any{"accepted": accepted, "schemaVersion": summary.SchemaVersion})
		if marshalError != nil {
			return 1, fmt.Errorf("encode release assessment JSON: %w", marshalError)
		}
		if _, writeError := fmt.Fprintln(application.Stdout, string(encoded)); writeError != nil {
			return 1, writeError
		}
		if err != nil {
			_, _ = fmt.Fprintln(application.Stderr, err)
			return guard.CapacityDeferredExitCode, nil
		}
		return 0, nil
	case "monitor":
		flags := flagSet("release monitor", application.Stderr)
		outputPath := flags.String("output", "", "sample output")
		summaryPath := flags.String("summary", "", "summary output")
		deploymentRoot := flags.String("deployment-root", "", "deployment root")
		durationMs := flags.Int64("duration-ms", 0, "optional duration in milliseconds")
		configPath, _ := configFlags(flags)
		if err := flags.Parse(arguments[1:]); err != nil {
			return 1, err
		}
		if *durationMs < 0 {
			return 1, errors.New("duration-ms must be nonnegative")
		}
		if _, configError := application.loadConfig(*configPath); configError != nil {
			return guard.ReplanRequiredExitCode, fmt.Errorf("resource configuration: %w", configError)
		}
		err := releaseguard.RunMonitor(releaseguard.MonitorConfig{OutputPath: *outputPath, SummaryPath: *summaryPath, DeploymentRoot: *deploymentRoot, Duration: time.Duration(*durationMs) * time.Millisecond, Collector: application.Collector, RoutedOrigin: os.Getenv("BNEST_PRODUCTION_ORIGIN")})
		if err != nil {
			return 1, err
		}
		return 0, nil
	default:
		return 1, errors.New("release requires check, monitor, or assess")
	}
}

// Execute runs the production application and writes command errors to stderr.
func Execute(arguments []string) int {
	code, err := (Application{}).Run(arguments)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		if code == 0 {
			return 1
		}
	}
	return code
}

// ParsePositiveInt parses an integer greater than zero.
func ParsePositiveInt(value string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return 0, errors.New("value must be a positive integer")
	}
	return parsed, nil
}
