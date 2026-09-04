namespace Badakmini.Cli.BehaviourTests

open System.Reflection
open TickSpec.Xunit
open global.Xunit

module private Resources =
    let private assembly = Assembly.GetExecutingAssembly()
    let source = AssemblyStepDefinitionsSource(assembly)
    let private catalog = lazy (FeatureCatalog.load assembly source)

    let private excludedTag =
        let contract = typeof<IBehaviourDriver>

        assembly.GetTypes()
        |> Array.find (fun candidate ->
            not candidate.IsAbstract
            && not candidate.IsInterface
            && contract.IsAssignableFrom candidate)
        |> _.Name
        |> function
            | name when name.Contains("IntegrationDriver") -> Some "integration-exempt"
            | name when name.Contains("E2eDriver") -> Some "e2e-exempt"
            | _unit -> None

    let scenarios () =
        catalog.Value
        |> Seq.collect _.Scenarios
        |> Seq.filter (fun scenario ->
            match excludedTag with
            | Some tag -> scenario.Tags |> Seq.contains tag |> not
            | None -> true)
        |> MemberData.ofScenarios

[<CollectionDefinition("Badakmini behaviours", DisableParallelization = true)>]
type BadakminiBehaviourCollection() = class end

[<Collection("Badakmini behaviours")>]
type Behaviours() =
    static member Scenarios() = Resources.scenarios ()

    [<Theory; MemberData("Scenarios")>]
    member _.Scenario(scenario: XunitSerializableScenario) = Resources.source.RunScenario scenario
