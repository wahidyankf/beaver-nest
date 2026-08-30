package guard

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sync/atomic"
	"syscall"
	"time"
)

const (
	// StorageBlockedExitCode indicates cleanup is required before retrying.
	StorageBlockedExitCode = 73
	// CapacityDeferredExitCode indicates transient pressure that should be retried.
	CapacityDeferredExitCode = 75
)

// RunConfig describes one guarded child process and its resource policy.
type RunConfig struct {
	Command                               string
	Arguments                             []string
	TaskClass                             string
	WorkingDirectory                      string
	Environment                           []string
	EvidenceRoot                          string
	DiskPath                              string
	LeasePort, LeaseMinimum, LeaseMaximum int
	LeaseOwner                            string
	PortLeaseRoot                         string
	Collector                             Collector
	Policy                                Policy
	Now                                   func() time.Time
	Sleep                                 func(time.Duration)
	Stderr                                io.Writer
}

func environmentValue(environment []string, name string) string {
	prefix := name + "="
	for _, entry := range environment {
		if len(entry) >= len(prefix) && entry[:len(prefix)] == prefix {
			return entry[len(prefix):]
		}
	}
	return ""
}

func withEnvironment(environment []string, name, value string) []string {
	result := make([]string, 0, len(environment)+1)
	prefix := name + "="
	for _, entry := range environment {
		if len(entry) < len(prefix) || entry[:len(prefix)] != prefix {
			result = append(result, entry)
		}
	}
	return append(result, prefix+value)
}

func waitStatusCode(err error) int {
	if err == nil {
		return 0
	}
	if exitError, ok := errors.AsType[*exec.ExitError](err); ok {
		if status, ok := exitError.Sys().(syscall.WaitStatus); ok {
			if status.Signaled() {
				return 128 + int(status.Signal())
			}
			return status.ExitStatus()
		}
	}
	return 1
}

func signalGroup(process *os.Process, signal syscall.Signal) {
	if process == nil {
		return
	}
	if err := syscall.Kill(-process.Pid, signal); err != nil {
		_ = process.Signal(signal)
	}
}

func directChild(config RunConfig, environment []string) int {
	command := exec.Command(config.Command, config.Arguments...)
	command.Dir = config.WorkingDirectory
	command.Env = environment
	command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
	return waitStatusCode(command.Run())
}

// Run admits, supervises, and records one child process without touching unrelated processes.
func Run(config RunConfig) (exitCode int, returnError error) {
	if config.Command == "" {
		return 1, errors.New("guarded command is empty")
	}
	if config.TaskClass == "" {
		config.TaskClass = "ephemeral"
	}
	if config.TaskClass != "ephemeral" && config.TaskClass != "service" && config.TaskClass != "transactional" {
		return 1, errors.New("class must be ephemeral, service, or transactional")
	}
	if config.Policy.SampleInterval == 0 {
		config.Policy = DevelopmentPolicy
	}
	if config.Collector == nil {
		return 1, errors.New("host collector is required")
	}
	if config.Now == nil {
		config.Now = time.Now
	}
	if config.Sleep == nil {
		config.Sleep = time.Sleep
	}
	if config.Stderr == nil {
		config.Stderr = os.Stderr
	}
	if config.Environment == nil {
		config.Environment = os.Environ()
	}
	if config.DiskPath == "" {
		config.DiskPath = config.WorkingDirectory
	}
	if config.DiskPath == "" {
		config.DiskPath = "."
	}
	if err := CleanupEvidence(config.EvidenceRoot, config.Now()); err != nil {
		return 1, err
	}
	session, err := AcquireSession(config.EvidenceRoot, environmentValue(config.Environment, "BNEST_RESOURCE_SESSION"), config.Policy.LeaseWait, config.Sleep)
	if err != nil {
		return 1, err
	}
	if session == nil {
		return CapacityDeferredExitCode, nil
	}
	defer func() {
		if releaseError := ReleaseSession(config.EvidenceRoot, session); returnError == nil && releaseError != nil {
			returnError = releaseError
			exitCode = 1
		}
	}()

	var portLease *PortLease
	if config.LeasePort != 0 {
		root := config.PortLeaseRoot
		if root == "" {
			root = filepath.Join(os.TempDir(), "bnest-port-leases")
		}
		portLease, err = AcquirePortLease(root, config.LeasePort, config.LeaseOwner, config.LeaseMinimum, config.LeaseMaximum)
		if err != nil {
			return 1, err
		}
		defer func() {
			if releaseError := ReleasePortLease(root, portLease); returnError == nil && releaseError != nil {
				returnError = releaseError
				exitCode = 1
			}
		}()
	}
	if session.Inherited {
		return directChild(config, config.Environment), nil
	}

	writer, err := NewEvidenceWriter(config.EvidenceRoot, EvidenceIdentifier("development-"+config.TaskClass, config.Now(), os.Getpid()))
	if err != nil {
		return 1, err
	}
	outcome := "capacity-deferred"
	finalized := false
	finalize := func() error {
		if finalized {
			return nil
		}
		finalized = true
		_, finalizeError := writer.Finalize(config.TaskClass, outcome, 0)
		return finalizeError
	}
	defer func() {
		if finalizeError := finalize(); returnError == nil && finalizeError != nil {
			returnError = finalizeError
			exitCode = 1
		}
	}()

	deadline := config.Now().Add(config.Policy.AdmissionWindow)
	var previous CPUState
	samples := []Sample{}
	for !config.Now().After(deadline) {
		reading, collectError := config.Collector.Collect(previous, config.DiskPath)
		if collectError != nil {
			return 1, collectError
		}
		previous = reading.CPUState
		samples = append(samples, reading.Sample)
		if appendError := writer.Append(reading.Sample); appendError != nil {
			return 1, appendError
		}
		assessment := ResourceAssessment(samples, config.Policy)
		if assessment.StorageBlocked {
			outcome = "storage-blocked"
			_, _ = fmt.Fprintf(config.Stderr, "Resource guard blocked task: %s; storage inspection or cleanup is required.\n", assessment.Reason)
			return StorageBlockedExitCode, nil
		}
		if AdmissionReady(samples, config.Policy) {
			break
		}
		config.Sleep(config.Policy.SampleInterval)
	}
	if !AdmissionReady(samples, config.Policy) {
		_, _ = fmt.Fprintln(config.Stderr, "Resource guard deferred task: safe admission was not reached.")
		return CapacityDeferredExitCode, nil
	}

	environment := withEnvironment(config.Environment, "BNEST_RESOURCE_SESSION", session.Token)
	executable, lookupError := exec.LookPath(config.Command)
	if lookupError != nil {
		return 1, lookupError
	}
	environment = withEnvironment(environment, "BNEST_RESOURCE_GUARD_BIN", executableGuardPath())
	command := exec.Command(executable, config.Arguments...)
	command.Dir = config.WorkingDirectory
	command.Env = environment
	command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if startError := command.Start(); startError != nil {
		return 1, startError
	}

	signalContext, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSignals()
	exited := make(chan error, 1)
	go func() { exited <- command.Wait() }()
	ticker := time.NewTicker(config.Policy.SampleInterval)
	defer ticker.Stop()
	var warningSince *time.Time
	shed, shedCode := false, CapacityDeferredExitCode
	var forceTimer *time.Timer
	var childExited atomic.Bool
	for {
		select {
		case waitError := <-exited:
			childExited.Store(true)
			if forceTimer != nil {
				forceTimer.Stop()
			}
			if !shed {
				if waitError == nil {
					outcome = "passed"
				} else {
					outcome = "task-failed"
				}
			}
			if cleanupError := CleanupEvidence(config.EvidenceRoot, config.Now()); cleanupError != nil {
				return 1, cleanupError
			}
			if shed {
				return shedCode, nil
			}
			return waitStatusCode(waitError), nil
		case <-signalContext.Done():
			signalGroup(command.Process, syscall.SIGTERM)
		case <-ticker.C:
			reading, collectError := config.Collector.Collect(previous, config.DiskPath)
			if collectError != nil {
				signalGroup(command.Process, syscall.SIGTERM)
				return 1, collectError
			}
			previous = reading.CPUState
			samples = append(samples, reading.Sample)
			limit := int(config.Policy.TrendWindow/config.Policy.SampleInterval) + 2
			if len(samples) > limit {
				samples = samples[len(samples)-limit:]
			}
			if appendError := writer.Append(reading.Sample); appendError != nil {
				signalGroup(command.Process, syscall.SIGTERM)
				return 1, appendError
			}
			assessment := ResourceAssessment(samples, config.Policy)
			if assessment.State == "normal" {
				warningSince = nil
			} else if assessment.State == "warning" && warningSince == nil {
				value := config.Now()
				warningSince = &value
			}
			if config.TaskClass == "transactional" || shed {
				continue
			}
			grace := config.Policy.EphemeralWarningGrace
			if config.TaskClass == "service" {
				grace = config.Policy.ServiceWarningGrace
			}
			if assessment.State == "critical" || (warningSince != nil && config.Now().Sub(*warningSince) >= grace) {
				shed = true
				if assessment.StorageBlocked {
					shedCode, outcome = StorageBlockedExitCode, "storage-shed"
				} else {
					outcome = "pressure-shed"
				}
				_, _ = fmt.Fprintf(config.Stderr, "Resource guard shedding %s child after %s.\n", config.TaskClass, assessment.Reason)
				signalGroup(command.Process, syscall.SIGTERM)
				forceTimer = time.AfterFunc(config.Policy.TerminationGrace, func() {
					if !childExited.Load() {
						signalGroup(command.Process, syscall.SIGKILL)
					}
				})
			}
		}
	}
}

func executableGuardPath() string {
	path, err := os.Executable()
	if err != nil {
		return ""
	}
	return path
}
