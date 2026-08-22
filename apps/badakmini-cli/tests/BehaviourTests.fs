namespace Badakmini.Cli.BehaviourTests

open System.Reflection
open TickSpec.Xunit
open global.Xunit

module private Resources =
    let source = AssemblyStepDefinitionsSource(Assembly.GetExecutingAssembly())

    let scenarios resourceName =
        source.ScenariosFromEmbeddedResource resourceName |> MemberData.ofScenarios

type WordBudgetBehaviours() =
    static member Scenarios() =
        Resources.scenarios "Badakmini.Cli.Specs.word-budget.feature"

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario

type DirectoryMapBehaviours() =
    static member Scenarios() =
        Resources.scenarios "Badakmini.Cli.Specs.directory-map.feature"

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario

type MermaidGovernanceBehaviours() =
    static member Scenarios() =
        Resources.scenarios "Badakmini.Cli.Specs.mermaid-governance.feature"

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario

[<CollectionDefinition("Process-global CLI behaviours", DisableParallelization = true)>]
type ProcessGlobalCliCollection() = class end

[<Collection("Process-global CLI behaviours")>]
type CliContractBehaviours() =
    static member Scenarios() =
        Resources.scenarios "Badakmini.Cli.Specs.cli-contract.feature"

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario

[<Collection("Process-global CLI behaviours")>]
type MermaidCliBehaviours() =
    static member Scenarios() =
        Resources.scenarios "Badakmini.Cli.Specs.mermaid-cli.feature"

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario
