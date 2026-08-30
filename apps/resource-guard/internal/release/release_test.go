package release_test

import (
	"slices"
	"testing"

	releaseguard "github.com/wahidyankf/beaver-nest/apps/resource-guard/internal/release"
)

func TestRoutedProbeFollowsOnlyBoundedRedirects(t *testing.T) {
	routed := releaseguard.HTTPProbeArguments("https://example.invalid/", true)
	if !slices.Contains(routed, "--location") || !slices.Contains(routed, "--max-redirs") || !slices.Contains(routed, "3") {
		t.Fatalf("routed probe does not follow bounded redirects: %v", routed)
	}

	local := releaseguard.HTTPProbeArguments("http://127.0.0.1:4100/health/ready", false)
	if slices.Contains(local, "--location") {
		t.Fatalf("local health probe unexpectedly follows redirects: %v", local)
	}
}
