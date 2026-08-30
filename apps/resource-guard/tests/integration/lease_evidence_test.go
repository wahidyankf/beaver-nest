package integration_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/guard"
)

func marshalJSON(t *testing.T, value any) []byte {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestHeavyLeaseLifecycleAndInheritance(t *testing.T) {
	root := t.TempDir()
	session, err := guard.AcquireSession(root, "", time.Second, func(time.Duration) {})
	if err != nil || session == nil || session.Inherited {
		t.Fatalf("acquire failed: session=%+v error=%v", session, err)
	}
	if !guard.InheritedSession(root, session.Token) || guard.InheritedSession(root, "") || guard.InheritedSession(root, "wrong") {
		t.Fatal("inheritance validation failed")
	}
	inherited, err := guard.AcquireSession(root, session.Token, 0, func(time.Duration) {})
	if err != nil || !inherited.Inherited {
		t.Fatalf("inherit failed: %+v %v", inherited, err)
	}
	deferred, err := guard.AcquireSession(root, "wrong", 0, func(time.Duration) {})
	if err != nil || deferred != nil {
		t.Fatalf("second owner was not deferred: %+v %v", deferred, err)
	}
	if err := guard.ReleaseSession(root, inherited); err != nil {
		t.Fatal(err)
	}
	if err := guard.ReleaseSession(root, session); err != nil {
		t.Fatal(err)
	}
	if err := guard.ReleaseSession(root, nil); err != nil {
		t.Fatal(err)
	}
}

func TestHeavyLeaseRejectsInvalidReleaseAndReclaimsStaleOwner(t *testing.T) {
	root := t.TempDir()
	lock := filepath.Join(root, "heavy.lock")
	if err := os.Mkdir(lock, 0o700); err != nil {
		t.Fatal(err)
	}
	marker := map[string]any{"schemaVersion": 1, "pid": 2_147_483_647, "token": "stale"}
	data := marshalJSON(t, marker)
	if err := os.WriteFile(filepath.Join(lock, "owner.json"), data, 0o600); err != nil {
		t.Fatal(err)
	}
	session, err := guard.AcquireSession(root, "", time.Second, func(time.Duration) {})
	if err != nil || session == nil {
		t.Fatalf("stale reclaim failed: %+v %v", session, err)
	}
	invalid := *session
	invalid.Path = filepath.Join(root, "other")
	if guard.ReleaseSession(root, &invalid) == nil {
		t.Fatal("invalid path release accepted")
	}
	ownerPath := filepath.Join(lock, "owner.json")
	ownerData, _ := os.ReadFile(ownerPath)
	var owner map[string]any
	_ = json.Unmarshal(ownerData, &owner)
	owner["token"] = "other"
	ownerData = marshalJSON(t, owner)
	_ = os.WriteFile(ownerPath, ownerData, 0o600)
	if guard.ReleaseSession(root, session) == nil {
		t.Fatal("foreign owner release accepted")
	}
	owner["token"] = session.Token
	ownerData = marshalJSON(t, owner)
	_ = os.WriteFile(ownerPath, ownerData, 0o600)
	if err := guard.ReleaseSession(root, session); err != nil {
		t.Fatal(err)
	}
}

func TestPortLeaseLifecycleValidationAndStaleRecovery(t *testing.T) {
	root := t.TempDir()
	if _, err := guard.AcquirePortLease(root, 10, "owner", 20, 30); err == nil {
		t.Fatal("out-of-range port accepted")
	}
	if _, err := guard.AcquirePortLease(root, 25, "INVALID", 20, 30); err == nil {
		t.Fatal("invalid owner accepted")
	}
	lease, err := guard.AcquirePortLease(root, 25, "first-owner", 20, 30)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := guard.AcquirePortLease(root, 25, "second-owner", 20, 30); err == nil {
		t.Fatal("live collision accepted")
	}
	invalid := *lease
	invalid.Path = filepath.Join(root, "invalid")
	if guard.ReleasePortLease(root, &invalid) == nil {
		t.Fatal("invalid release accepted")
	}
	ownerPath := filepath.Join(lease.Path, "owner.json")
	data, _ := os.ReadFile(ownerPath)
	var owner map[string]any
	_ = json.Unmarshal(data, &owner)
	owner["owner"] = "other"
	data = marshalJSON(t, owner)
	_ = os.WriteFile(ownerPath, data, 0o600)
	if guard.ReleasePortLease(root, lease) == nil {
		t.Fatal("foreign port release accepted")
	}
	owner["owner"] = lease.Owner
	data = marshalJSON(t, owner)
	_ = os.WriteFile(ownerPath, data, 0o600)
	if err := guard.ReleasePortLease(root, lease); err != nil {
		t.Fatal(err)
	}
	if err := guard.ReleasePortLease(root, nil); err != nil {
		t.Fatal(err)
	}
	stalePath := filepath.Join(root, "26.lock")
	_ = os.Mkdir(stalePath, 0o700)
	stale := marshalJSON(t, map[string]any{"schemaVersion": 1, "pid": 2_147_483_647, "port": 26, "owner": "stale"})
	_ = os.WriteFile(filepath.Join(stalePath, "owner.json"), stale, 0o600)
	replacement, err := guard.AcquirePortLease(root, 26, "replacement", 20, 30)
	if err != nil {
		t.Fatal(err)
	}
	if err := guard.ReleasePortLease(root, replacement); err != nil {
		t.Fatal(err)
	}
}

func TestEvidenceLifecycleSummaryAndCleanup(t *testing.T) {
	root := t.TempDir()
	now := time.Unix(2_000_000, 0)
	if err := guard.CleanupEvidence(root, now); err != nil {
		t.Fatal(err)
	}
	old := filepath.Join(root, "old.jsonl")
	summaryOld := filepath.Join(root, "old.summary.json")
	preserve := filepath.Join(root, "preserve.jsonl")
	for _, path := range []string{old, summaryOld, preserve} {
		if err := os.WriteFile(path, []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
		stale := now.Add(-31 * 24 * time.Hour)
		_ = os.Chtimes(path, stale, stale)
	}
	if err := guard.CleanupEvidence(root, now, preserve); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatal("expired evidence retained")
	}
	if _, err := os.Stat(summaryOld); !os.IsNotExist(err) {
		t.Fatal("expired summary retained")
	}
	if _, err := os.Stat(preserve); err != nil {
		t.Fatal("preserved evidence removed")
	}
	writer, err := guard.NewEvidenceWriter(root, guard.EvidenceIdentifier("integration/test", now, os.Getpid()))
	if err != nil {
		t.Fatal(err)
	}
	writer.SetContext(guard.Resolution{RequestedProfile: "balanced", ResolvedProfile: "minimal", FallbackChain: []string{"balanced", "minimal"}, Concurrency: 1}, "config-hash")
	one := int64(1)
	two := int64(2)
	levelOne := 1
	levelTwo := 2
	yes := true
	no := false
	cpuOne, cpuTwo := 10.0, 20.0
	first := guard.Sample{AvailableParallelism: 8, AvailableNonCompressedEstimateBytes: &two, MemoryPressureLevel: &levelOne, CompressorAvailable: &yes, CompressorPayloadBytes: &one, CPUUtilizationPercent: &cpuOne, DiskFreeBytes: &two, SwapIns: &one, SwapOuts: &one, SwapFreeBytes: &two}
	second := guard.Sample{AvailableParallelism: 8, AvailableNonCompressedEstimateBytes: &one, MemoryPressureLevel: &levelTwo, CompressorAvailable: &no, CompressorPayloadBytes: &two, CPUUtilizationPercent: &cpuTwo, DiskFreeBytes: &one, SwapIns: &two, SwapOuts: &two, SwapFreeBytes: &one}
	if err := writer.Append(first); err != nil {
		t.Fatal(err)
	}
	if err := writer.Append(second); err != nil {
		t.Fatal(err)
	}
	summary, err := writer.Finalize("ephemeral", "passed", 1)
	if err != nil {
		t.Fatal(err)
	}
	if summary.SchemaVersion != 3 || summary.SampleCount != 2 || summary.CompressorAvailableAll || summary.SwapInsDelta != 1 || summary.SwapOutsDelta != 1 || summary.HealthFailures != 1 || summary.ResolvedProfile != "minimal" || summary.ConfigHash != "config-hash" {
		t.Fatalf("unexpected summary %+v", summary)
	}
	if _, err := writer.Finalize("ephemeral", "passed", 0); err == nil {
		t.Fatal("second finalize accepted")
	}
}
