package unit_test

import (
	"testing"

	"github.com/cucumber/godog"
	"github.com/wahidyankf/beaver-nest/tools/resource-guard/tests/support"
)

func TestUnitBehaviours(t *testing.T) {
	driver := &support.Driver{Mode: "unit"}
	defer driver.Close()
	status := godog.TestSuite{Name: "resource-guard-unit", ScenarioInitializer: driver.Initialize, Options: &godog.Options{Format: "progress", Paths: []string{support.FeaturePath}, Tags: "~@unit-exempt", TestingT: t}}.Run()
	if status != 0 {
		t.Fatalf("unit behaviour suite exited %d", status)
	}
}
