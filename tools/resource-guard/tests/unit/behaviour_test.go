package unit_test

import (
	"testing"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/tests/contract"
	"github.com/wahidyankf/beaver-nest/tools/resource-guard/tests/support"
)

func TestUnitBehaviours(t *testing.T) {
	adapter, err := contract.AdapterByName(contract.Unit)
	if err != nil {
		t.Fatal(err)
	}
	contract.Run(t, adapter, support.NewDriver(adapter))
}
