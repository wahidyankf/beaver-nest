namespace Badakmini.Cli.BehaviourTests

open System.Reflection
open TickSpec.Xunit
open global.Xunit

module private Resources =
    let private assembly = Assembly.GetExecutingAssembly()
    let source = AssemblyStepDefinitionsSource(assembly)
    let private catalog = lazy (FeatureCatalog.load assembly source)

    let scenarios () =
        catalog.Value |> Seq.collect _.Scenarios |> MemberData.ofScenarios

[<CollectionDefinition("Badakmini behaviours", DisableParallelization = true)>]
type BadakminiBehaviourCollection() = class end

[<Collection("Badakmini behaviours")>]
type Behaviours() =
    static member Scenarios() = Resources.scenarios ()

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario
