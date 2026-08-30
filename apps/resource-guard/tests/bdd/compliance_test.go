package bdd_test

import (
	"os"
	"strings"
	"testing"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/tests/contract"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/tests/support"
)

var _ contract.Driver = (*support.Driver)(nil)

func TestFeatureCompliance(t *testing.T) {
	requested := os.Getenv("RESOURCE_GUARD_BDD_ADAPTER")
	if requested != "" {
		adapter, err := contract.AdapterByName(requested)
		if err != nil {
			t.Fatal(err)
		}
		verifyAdapter(t, adapter)
		return
	}
	for _, adapter := range contract.Adapters() {
		t.Run(adapter.Name, func(t *testing.T) { verifyAdapter(t, adapter) })
	}
}

func TestScenarioWithoutActionAndOutcomeIsRejected(t *testing.T) {
	err := contract.ValidateScenarioStructure("incomplete", []string{"Context", "Context"})
	if err == nil {
		t.Fatal("scenario without explicit When and Then was accepted")
	}
}

func TestUndefinedBindingIsRejected(t *testing.T) {
	errorsFound := contract.ValidateBindings(
		[]contract.StepDefinition{{Pattern: `^known$`}},
		[]string{"known", "unknown"},
	)
	requireErrorContaining(t, errorsFound, "undefined behavior step")
}

func TestAmbiguousBindingIsRejected(t *testing.T) {
	errorsFound := contract.ValidateBindings(
		[]contract.StepDefinition{{Pattern: `^duplicate$`}, {Pattern: `^duplicate$`}},
		[]string{"duplicate"},
	)
	requireErrorContaining(t, errorsFound, "ambiguous behavior step")
}

func TestUnusedBindingIsRejected(t *testing.T) {
	errorsFound := contract.ValidateBindings(
		[]contract.StepDefinition{{Pattern: `^used$`}, {Pattern: `^unused$`}},
		[]string{"used"},
	)
	requireErrorContaining(t, errorsFound, "unused behavior binding")
}

func TestUnapprovedExemptionIsRejected(t *testing.T) {
	adapter, err := contract.AdapterByName(contract.Integration)
	if err != nil {
		t.Fatal(err)
	}
	errorsFound := contract.ValidateExemptions(adapter, []contract.Scenario{{
		Name: "unapproved",
		Tags: []string{"@integration-exempt"},
	}})
	requireErrorContaining(t, errorsFound, "unknown exemption tag")
}

func verifyAdapter(t *testing.T, adapter contract.Adapter) {
	t.Helper()
	if !contract.SuiteOptions(adapter).Strict {
		t.Fatalf("%s adapter is not strict", adapter.Name)
	}
	if err := contract.Verify(adapter); err != nil {
		t.Fatal(err)
	}
}

func requireErrorContaining(t *testing.T, errorsFound []error, expected string) {
	t.Helper()
	for _, err := range errorsFound {
		if strings.Contains(err.Error(), expected) {
			return
		}
	}
	t.Fatalf("expected error containing %q, got %v", expected, errorsFound)
}
