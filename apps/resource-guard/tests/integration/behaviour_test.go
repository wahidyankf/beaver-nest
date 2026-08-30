package integration_test

import (
	"testing"

	"github.com/wahidyankf/beaver-nest/apps/resource-guard/tests/contract"
	"github.com/wahidyankf/beaver-nest/apps/resource-guard/tests/support"
)

func TestIntegrationBehaviours(t *testing.T) {
	adapter, err := contract.AdapterByName(contract.Integration)
	if err != nil {
		t.Fatal(err)
	}
	contract.Run(t, adapter, support.NewDriver(adapter))
}
