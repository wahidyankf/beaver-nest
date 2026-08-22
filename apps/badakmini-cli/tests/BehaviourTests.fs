namespace Badakmini.Cli.BehaviourTests

open System.Reflection
open TickSpec.Xunit
open global.Xunit

module private Resources =
    let private assembly = Assembly.GetExecutingAssembly()
    let source = AssemblyStepDefinitionsSource(assembly)
    let private catalog = lazy (FeatureCatalog.load assembly source)

    let scenarios boundary =
        catalog.Value
        |> Seq.filter (fun feature -> feature.Boundary = boundary)
        |> Seq.collect _.Scenarios
        |> MemberData.ofScenarios

type PureBehaviours() =
    static member Scenarios() = Resources.scenarios Pure

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario

[<CollectionDefinition("Process-global CLI behaviours", DisableParallelization = true)>]
type ProcessGlobalCliCollection() = class end

[<Collection("Process-global CLI behaviours")>]
type ProcessGlobalBehaviours() =
    static member Scenarios() = Resources.scenarios ProcessGlobal

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario
