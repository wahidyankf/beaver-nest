package bdd_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/wahidyankf/beaver-nest/tools/resource-guard/tests/support"
)

func TestFeatureCorpusAndBindingsAreComplete(t *testing.T) {
	root := "../../../../specs/tools/resource-guard/behaviours"
	features := []string{}
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, walkError error) error {
		if walkError != nil {
			return walkError
		}
		if !entry.IsDir() && filepath.Ext(path) == ".feature" {
			features = append(features, path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(features) != 4 {
		t.Fatalf("expected exact recursive corpus of four features, got %d", len(features))
	}
	used := make([]bool, len(support.Definitions))
	for _, path := range features {
		data, readError := os.ReadFile(path)
		if readError != nil {
			t.Fatal(readError)
		}
		lines := strings.Split(string(data), "\n")
		scenario, when, then := "", false, false
		finish := func() {
			if scenario != "" && (!when || !then) {
				t.Errorf("%s scenario %q requires explicit When and Then", path, scenario)
			}
		}
		for _, raw := range lines {
			line := strings.TrimSpace(raw)
			if strings.HasPrefix(line, "Scenario:") {
				finish()
				scenario = strings.TrimSpace(strings.TrimPrefix(line, "Scenario:"))
				when, then = false, false
				if scenario == "" {
					t.Errorf("%s has empty scenario", path)
				}
				continue
			}
			prefixes := []string{"Given ", "When ", "Then ", "And "}
			step := ""
			for _, prefix := range prefixes {
				if strings.HasPrefix(line, prefix) {
					step = strings.TrimPrefix(line, prefix)
					if prefix == "When " {
						when = true
					}
					if prefix == "Then " {
						then = true
					}
					break
				}
			}
			if step == "" {
				continue
			}
			for _, adapter := range []string{"unit", "integration", "e2e"} {
				if count := support.MatchCount(step, adapter); count != 1 {
					t.Errorf("%s step %q resolves %d times in %s", path, step, count, adapter)
				}
			}
			for index, definition := range support.Definitions {
				if support.MatchCount(step, "unit") == 1 && definition.Adapters["unit"] { // exact registry use is checked by pattern text below
					if strings.Trim(definition.Pattern, "^$") == step {
						used[index] = true
					}
				}
			}
		}
		finish()
	}
	for index, wasUsed := range used {
		if !wasUsed {
			t.Errorf("unused binding %q", support.Definitions[index].Pattern)
		}
	}
}
