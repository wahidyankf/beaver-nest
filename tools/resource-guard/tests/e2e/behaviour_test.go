package e2e_test

import (
	"testing"

	"github.com/cucumber/godog"
	"github.com/wahidyankf/beaver-nest/tools/resource-guard/tests/support"
)

func TestE2EBehaviours(t *testing.T) {
	driver := &support.Driver{Mode: "e2e"}
	status := godog.TestSuite{Name: "resource-guard-e2e", ScenarioInitializer: driver.Initialize, Options: &godog.Options{Format: "progress", Paths: []string{support.FeaturePath}, Tags: "~@e2e-exempt", TestingT: t}}.Run()
	if status != 0 {
		t.Fatalf("e2e behaviour suite exited %d", status)
	}
}
