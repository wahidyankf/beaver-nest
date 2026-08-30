package integration_test

import (
	"testing"

	"github.com/cucumber/godog"
	"github.com/wahidyankf/beaver-nest/tools/resource-guard/tests/support"
)

func TestIntegrationBehaviours(t *testing.T) {
	driver := &support.Driver{Mode: "integration"}
	defer driver.Close()
	status := godog.TestSuite{Name: "resource-guard-integration", ScenarioInitializer: driver.Initialize, Options: &godog.Options{Format: "progress", Paths: []string{support.FeaturePath}, TestingT: t}}.Run()
	if status != 0 {
		t.Fatalf("integration behaviour suite exited %d", status)
	}
}
