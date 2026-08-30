package contract

import (
	"errors"
	"fmt"
	"io/fs"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/cucumber/godog"
	messages "github.com/cucumber/messages/go/v34"
)

const (
	// FeaturePath points every adapter at the canonical recursive Gherkin corpus.
	FeaturePath = "../../../../specs/apps/resource-guard/behaviours"
	// Unit identifies the deterministic in-process adapter.
	Unit = "unit"
	// Integration identifies the local filesystem and process adapter.
	Integration = "integration"
	// E2E identifies the compiled public-binary adapter.
	E2E = "e2e"
)

// StepDefinition declares one canonical Godog expression.
type StepDefinition struct {
	Pattern string
}

// Definitions is the complete shared binding registry.
var Definitions = []StepDefinition{
	{`^three healthy host samples$`},
	{`^development admission is assessed$`},
	{`^the work is admitted$`},
	{`^admission is storage blocked with exit 73$`},
	{`^swap-outs grow by 128 MiB over 15 seconds$`},
	{`^development pressure is assessed$`},
	{`^the state is warning because of swap pressure$`},
	{`^compressor payload is 12 GiB and grows 1 GiB over 15 seconds$`},
	{`^the state is warning because of compressor pressure$`},
	{`^another live process owns the heavy lease$`},
	{`^a second owner waits for the lease$`},
	{`^the second owner is deferred with exit 75$`},
	{`^a valid inherited resource session$`},
	{`^a guarded child exits successfully$`},
	{`^the child exit code is preserved$`},
	{`^an admitted guarded command$`},
	{`^the guarded child exits with code 17$`},
	{`^the guard exits with code 17$`},
	{`^an admitted ephemeral child encounters critical pressure$`},
	{`^the guard observes the critical sample$`},
	{`^only the guarded child group is terminated with exit 75$`},
	{`^the compiled resource guard binary$`},
	{`^JSON status is requested for an existing path$`},
	{`^status returns schema version 3 with profile and capability evidence$`},
	{`^run is requested without a command separator$`},
	{`^the command fails with a useful validation error$`},
	{`^a healthy release summary file$`},
	{`^release summary assessment is requested$`},
	{`^the release evidence is accepted$`},
	{`^a release host below its requested balanced capacity$`},
	{`^release admission is assessed$`},
	{`^the release requires replanning instead of automatic fallback$`},
	{`^a release summary with one health failure$`},
	{`^release overlap evidence is assessed$`},
	{`^the release evidence is rejected$`},
	{`^a release summary outside the routed responsiveness budget$`},
	{`^the resource guard Nx build configuration$`},
	{`^build artifact caching is inspected$`},
	{`^compiled binaries are excluded from the Nx cache$`},
	{`^the resource guard end-to-end harness$`},
	{`^its compiled binary lifecycle is inspected$`},
	{`^the end-to-end binary is removed after the run$`},
	{`^four historical bootstrap generations$`},
	{`^the current bootstrap generation runs$`},
	{`^only the current and two recent generations remain$`},
	{`^the resource guard Go lint configuration$`},
	{`^lint enforcement is inspected$`},
	{`^every available linter is enabled with documented exceptions$`},
	{`^package documentation is enforced$`},
	{`^lint remains scoped to the resource guard module$`},
	{`^the resource guard Gherkin adapter contract$`},
	{`^behavior coverage enforcement is inspected$`},
	{`^unit integration and end-to-end suites use strict step resolution$`},
	{`^every behavior exemption has an approved adapter reason$`},
	{`^behavior compliance runs serially for every adapter$`},
	{`^full end-to-end behavior remains outside quick checks$`},
	{`^a healthy 5 GiB runner without swap$`},
	{`^the constrained profile is selected$`},
	{`^a healthy 1 GiB machine without swap$`},
	{`^the minimal profile is selected with concurrency one$`},
	{`^a host sample below the 256 MiB disk floor$`},
	{`^a strict transactional task that does not fit its requested profile$`},
	{`^admission requires replanning with exit 78$`},
	{`^Linux reports 16 GiB host memory and a 4 GiB cgroup limit$`},
	{`^the Linux evidence is collected$`},
	{`^effective memory is 4 GiB$`},
	{`^Linux reports no usable swap$`},
	{`^swap is unavailable without causing critical pressure$`},
	{`^Linux memory PSI some average is 10 percent$`},
	{`^the state is warning because of memory PSI$`},
	{`^an explicit resource guard config with an unknown field$`},
	{`^JSON status is requested with that config$`},
	{`^configuration fails with exit 78$`},
	{`^the resource guard artifact policy$`},
	{`^tracked and ignored paths are inspected$`},
	{`^local config and compiled binaries are rejected from Git$`},
	{`^the local config example remains tracked$`},
	{`^the application layout has no legacy tools trees$`},
}

// Adapter describes one behavior layer and its exemption tag.
type Adapter struct {
	Name         string
	ExemptionTag string
}

// Exemption documents why one scenario cannot run through an adapter.
type Exemption struct {
	Scenario string
	Reason   string
}

// ApprovedExemptions is the reviewed, exact adapter exemption inventory.
var ApprovedExemptions = map[string][]Exemption{
	Unit: {
		{"Nx does not retain compiled build snapshots", "requires repository project configuration"},
		{"End-to-end binaries are temporary", "requires subprocess and filesystem lifecycle access"},
		{"Bootstrap cache retention is bounded", "requires the real bootstrap and filesystem cache"},
		{"Strict lint is exhaustive and module scoped", "requires repository lint configuration"},
		{"Every behavior adapter has enforced compliance", "requires repository test configuration"},
		{"Machine-local configuration and binaries stay private", "requires the repository Git index and ignore rules"},
	},
	Integration: {},
	E2E: {
		{"Healthy consecutive samples admit work", "requires synthetic host pressure samples"},
		{"Balanced work falls back on a small runner", "requires synthetic host capacity"},
		{"Minimal work still runs on a tiny machine", "requires synthetic host capacity"},
		{"Exhausted storage requires cleanup", "requires synthetic disk evidence"},
		{"Swap-out growth is normalized to the policy window", "requires synthetic swap counters"},
		{"Compressor growth requires both payload and growth", "requires synthetic compressor counters"},
		{"A strict transaction does not silently downgrade", "requires synthetic task capacity"},
		{"Linux cgroup memory limits host capacity", "requires synthetic proc and cgroup files"},
		{"Linux without swap remains usable", "requires synthetic swap capabilities"},
		{"Linux PSI detects active memory contention", "requires synthetic PSI evidence"},
		{"A live heavy lease defers a second owner", "would mutate live lease ownership"},
		{"Critical pressure sheds eligible work", "requires synthetic critical pressure and process signaling"},
		{"Release admission preserves the requested capacity envelope", "requires synthetic release host samples"},
		{"Release overlap rejects failed health evidence", "requires synthetic failed health evidence"},
		{"Release overlap rejects an unresponsive routed journey", "requires synthetic routed-latency evidence"},
		{"Nx does not retain compiled build snapshots", "requires repository project configuration"},
		{"End-to-end binaries are temporary", "inspects the test harness rather than the public binary"},
		{"Bootstrap cache retention is bounded", "mutates a synthetic bootstrap cache"},
		{"Strict lint is exhaustive and module scoped", "requires repository lint configuration"},
		{"Every behavior adapter has enforced compliance", "requires repository test configuration"},
		{"Invalid explicit configuration is actionable", "requires an intentionally invalid local configuration"},
		{"Machine-local configuration and binaries stay private", "inspects repository Git policy rather than the public binary"},
	},
}

// Scenario is the compliance view of one compiled Gherkin scenario.
type Scenario struct {
	Name  string
	Steps []string
	Tags  []string
}

// Driver is the shared contract implemented by every behavior adapter.
type Driver interface {
	Initialize(scenarioContext *godog.ScenarioContext)
	Close()
}

// Adapters returns the complete behavior adapter inventory in execution order.
func Adapters() []Adapter {
	return []Adapter{
		{Name: Unit, ExemptionTag: "@unit-exempt"},
		{Name: Integration},
		{Name: E2E, ExemptionTag: "@e2e-exempt"},
	}
}

// AdapterByName returns one configured adapter.
func AdapterByName(name string) (Adapter, error) {
	for _, adapter := range Adapters() {
		if adapter.Name == name {
			return adapter, nil
		}
	}
	return Adapter{}, fmt.Errorf("unknown behavior adapter %q", name)
}

// SuiteOptions returns strict Godog options shared by compliance and execution.
func SuiteOptions(adapter Adapter) *godog.Options {
	tags := ""
	if adapter.ExemptionTag != "" {
		tags = "~" + adapter.ExemptionTag
	}
	return &godog.Options{Format: "progress", Paths: []string{FeaturePath}, Tags: tags, Strict: true}
}

// Run executes the canonical corpus through one strict adapter.
func Run(t *testing.T, adapter Adapter, driver Driver) {
	t.Helper()
	defer driver.Close()
	options := SuiteOptions(adapter)
	options.TestingT = t
	status := godog.TestSuite{Name: "resource-guard-" + adapter.Name, ScenarioInitializer: driver.Initialize, Options: options}.Run()
	if status != 0 {
		t.Fatalf("%s behavior suite exited %d", adapter.Name, status)
	}
}

// ValidateScenarioStructure requires an explicit action and outcome.
func ValidateScenarioStructure(name string, keywordTypes []string) error {
	hasAction, hasOutcome := false, false
	for _, keywordType := range keywordTypes {
		hasAction = hasAction || keywordType == "Action"
		hasOutcome = hasOutcome || keywordType == "Outcome"
	}
	if !hasAction || !hasOutcome {
		return fmt.Errorf("scenario %q requires explicit When and Then steps", name)
	}
	return nil
}

// ValidateBindings rejects invalid expressions, undefined or ambiguous steps, and unused bindings.
func ValidateBindings(definitions []StepDefinition, steps []string) []error {
	compiled := make([]*regexp.Regexp, len(definitions))
	errorsFound := []error{}
	for index, definition := range definitions {
		expression, err := regexp.Compile(definition.Pattern)
		if err != nil {
			errorsFound = append(errorsFound, fmt.Errorf("invalid binding %q: %w", definition.Pattern, err))
			continue
		}
		compiled[index] = expression
	}
	used := make([]bool, len(definitions))
	for _, step := range steps {
		matches := []int{}
		for index, expression := range compiled {
			if expression != nil && expression.MatchString(step) {
				matches = append(matches, index)
			}
		}
		switch len(matches) {
		case 0:
			errorsFound = append(errorsFound, fmt.Errorf("undefined behavior step %q", step))
		case 1:
			used[matches[0]] = true
		default:
			errorsFound = append(errorsFound, fmt.Errorf("ambiguous behavior step %q", step))
		}
	}
	for index, wasUsed := range used {
		if !wasUsed && compiled[index] != nil {
			errorsFound = append(errorsFound, fmt.Errorf("unused behavior binding %q", definitions[index].Pattern))
		}
	}
	return errorsFound
}

// ValidateExemptions requires exact reviewed tags and nonempty reasons.
func ValidateExemptions(adapter Adapter, scenarios []Scenario) []error {
	errorsFound := []error{}
	approved := map[string]string{}
	for _, exemption := range ApprovedExemptions[adapter.Name] {
		if strings.TrimSpace(exemption.Reason) == "" {
			errorsFound = append(errorsFound, fmt.Errorf("%s exemption %q has no reason", adapter.Name, exemption.Scenario))
		}
		approved[exemption.Scenario] = exemption.Reason
	}
	seen := map[string]bool{}
	knownTags := map[string]bool{"@unit-exempt": true, "@e2e-exempt": true}
	for _, scenario := range scenarios {
		tagged := false
		for _, tag := range scenario.Tags {
			if strings.HasSuffix(tag, "-exempt") && !knownTags[tag] {
				errorsFound = append(errorsFound, fmt.Errorf("scenario %q uses unknown exemption tag %q", scenario.Name, tag))
			}
			tagged = tagged || tag == adapter.ExemptionTag
		}
		_, expected := approved[scenario.Name]
		if tagged != expected {
			errorsFound = append(errorsFound, fmt.Errorf("%s exemption mismatch for scenario %q", adapter.Name, scenario.Name))
		}
		if tagged {
			seen[scenario.Name] = true
		}
	}
	for scenario := range approved {
		if !seen[scenario] {
			errorsFound = append(errorsFound, fmt.Errorf("approved %s exemption %q is absent", adapter.Name, scenario))
		}
	}
	return errorsFound
}

type corpusInspection struct {
	scenarios       []Scenario
	steps           []string
	structuralError []error
	astScenarios    int
}

func countDiskFeatures() (int, error) {
	count := 0
	err := filepath.WalkDir(FeaturePath, func(path string, entry fs.DirEntry, walkError error) error {
		if walkError != nil {
			return walkError
		}
		if !entry.IsDir() && filepath.Ext(path) == ".feature" {
			count++
		}
		return nil
	})
	return count, err
}

func inspectScenario(scenario *messages.Scenario) error {
	keywords := make([]string, 0, len(scenario.Steps))
	for _, step := range scenario.Steps {
		keywords = append(keywords, step.KeywordType.String())
	}
	return ValidateScenarioStructure(scenario.Name, keywords)
}

func inspectFeature(uri string, feature *messages.Feature, pickles []*messages.Pickle) corpusInspection {
	inspection := corpusInspection{}
	if feature == nil {
		inspection.structuralError = append(inspection.structuralError, fmt.Errorf("%s has no Feature declaration", uri))
		return inspection
	}
	for _, child := range feature.Children {
		if scenario := child.Scenario; scenario != nil {
			inspection.astScenarios++
			if err := inspectScenario(scenario); err != nil {
				inspection.structuralError = append(inspection.structuralError, err)
			}
		}
		if rule := child.Rule; rule != nil {
			inspection.inspectRule(rule)
		}
	}
	inspection.inspectPickles(pickles)
	return inspection
}

func (inspection *corpusInspection) inspectRule(rule *messages.Rule) {
	for _, child := range rule.Children {
		if scenario := child.Scenario; scenario != nil {
			inspection.astScenarios++
			if err := inspectScenario(scenario); err != nil {
				inspection.structuralError = append(inspection.structuralError, err)
			}
		}
	}
}

func (inspection *corpusInspection) inspectPickles(pickles []*messages.Pickle) {
	for _, pickle := range pickles {
		scenario := Scenario{Name: pickle.Name}
		for _, step := range pickle.Steps {
			scenario.Steps = append(scenario.Steps, step.Text)
			inspection.steps = append(inspection.steps, step.Text)
		}
		for _, tag := range pickle.Tags {
			scenario.Tags = append(scenario.Tags, tag.Name)
		}
		inspection.scenarios = append(inspection.scenarios, scenario)
	}
}

func mergeInspection(target *corpusInspection, source corpusInspection) {
	target.scenarios = append(target.scenarios, source.scenarios...)
	target.steps = append(target.steps, source.steps...)
	target.structuralError = append(target.structuralError, source.structuralError...)
	target.astScenarios += source.astScenarios
}

func runnableScenarios(adapter Adapter, scenarios []Scenario) int {
	count := 0
	for _, scenario := range scenarios {
		exempt := false
		for _, tag := range scenario.Tags {
			exempt = exempt || tag == adapter.ExemptionTag
		}
		if !exempt {
			count++
		}
	}
	return count
}

func combineErrors(errorsFound []error) error {
	if len(errorsFound) == 0 {
		return nil
	}
	messagesFound := make([]string, 0, len(errorsFound))
	for _, found := range errorsFound {
		messagesFound = append(messagesFound, found.Error())
	}
	sort.Strings(messagesFound)
	return errors.New(strings.Join(messagesFound, "\n"))
}

// Verify validates the recursive corpus, bindings, structure, and one adapter policy.
func Verify(adapter Adapter) error {
	corpusOptions := &godog.Options{Paths: []string{FeaturePath}, Strict: true}
	features, err := (godog.TestSuite{Options: corpusOptions}).RetrieveFeatures()
	if err != nil {
		return fmt.Errorf("retrieve behavior corpus: %w", err)
	}
	diskFeatures, err := countDiskFeatures()
	if err != nil {
		return fmt.Errorf("walk behavior corpus: %w", err)
	}
	if diskFeatures == 0 || len(features) != diskFeatures {
		return fmt.Errorf("parsed %d of %d canonical behavior features", len(features), diskFeatures)
	}

	inspection := corpusInspection{}
	for _, feature := range features {
		mergeInspection(&inspection, inspectFeature(feature.Uri, feature.Feature, feature.Pickles))
	}
	if inspection.astScenarios == 0 || len(inspection.scenarios) == 0 {
		inspection.structuralError = append(inspection.structuralError, errors.New("behavior corpus has no scenarios"))
	}
	inspection.structuralError = append(inspection.structuralError, ValidateBindings(Definitions, inspection.steps)...)
	inspection.structuralError = append(inspection.structuralError, ValidateExemptions(adapter, inspection.scenarios)...)
	if runnableScenarios(adapter, inspection.scenarios) == 0 {
		inspection.structuralError = append(inspection.structuralError, fmt.Errorf("%s adapter runs no scenarios", adapter.Name))
	}
	return combineErrors(inspection.structuralError)
}
