namespace Badakmini.Cli.BehaviourTests

open System
open System.IO
open System.Reflection
open TickSpec
open TickSpec.Xunit
open global.Xunit

type FeatureComplianceTests() =
    let assertErrorContains (expected: string) source =
        match FeatureCompliance.validate "example.feature" source with
        | Error errors -> Assert.Contains(errors, fun error -> error.Contains expected)
        | Ok() -> failwithf "Expected compliance failure containing '%s'." expected

    [<Fact>]
    member _.``feature and scenario tags remain available``() =
        let source =
            "@documentation\nFeature: Compliance example\n\n  @smoke\n  Scenario: Tagged behavior\n    Given a precondition\n    When an action occurs\n    Then an outcome is observed"

        Assert.Equal(Ok(), FeatureCompliance.validate "example.feature" source)

    [<Fact>]
    member _.``missing feature declaration is rejected``() =
        "Scenario: Orphan\n  When an action occurs\n  Then an outcome is observed"
        |> assertErrorContains "missing Feature:"

    [<Fact>]
    member _.``feature without scenarios is rejected``() =
        "Feature: Empty feature" |> assertErrorContains "at least one scenario"

    [<Fact>]
    member _.``scenario without When is rejected``() =
        "Feature: Compliance example\n\n  Scenario: Missing action\n    Given a precondition\n    Then an outcome is observed"
        |> assertErrorContains "requires a When step"

    [<Fact>]
    member _.``scenario without Then is rejected``() =
        "Feature: Compliance example\n\n  Scenario: Missing outcome\n    Given a precondition\n    When an action occurs"
        |> assertErrorContains "requires a Then step"

    [<Fact>]
    member _.``all TickSpec hooks and steps live in the thin binding module``() =
        let tickSpecAttributeNames =
            set
                [ "BeforeScenarioAttribute"
                  "GivenAttribute"
                  "WhenAttribute"
                  "ThenAttribute" ]

        let attributedMethods =
            Assembly.GetExecutingAssembly().GetTypes()
            |> Array.collect (fun reflectedType ->
                reflectedType.GetMethods(BindingFlags.Public ||| BindingFlags.NonPublic ||| BindingFlags.Static)
                |> Array.filter (fun methodInfo ->
                    methodInfo.GetCustomAttributes(false)
                    |> Array.exists (fun attribute -> tickSpecAttributeNames.Contains(attribute.GetType().Name))))

        Assert.NotEmpty attributedMethods

        Assert.All(
            attributedMethods,
            fun methodInfo -> Assert.Equal("Badakmini.Cli.BehaviourSteps", methodInfo.DeclaringType.FullName)
        )

    [<Fact>]
    member _.``canonical feature corpus resolves every scenario and binding exactly once``() =
        let assembly = Assembly.GetExecutingAssembly()
        let source = AssemblyStepDefinitionsSource assembly
        let catalog = FeatureCatalog.load assembly source
        let scenarioCount = catalog |> Array.sumBy (fun feature -> feature.Scenarios.Length)

        let expectedScenarioCount =
            catalog
            |> Array.sumBy (fun feature ->
                let featureSource = FeatureCatalog.readResource assembly feature.ResourceName

                FeatureParser.parseFeature (featureSource.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
                |> _.Scenarios.Length)

        let steps =
            catalog
            |> Array.collect (fun feature ->
                FeatureCatalog.readResource assembly feature.ResourceName
                |> BindingCompliance.steps
                |> List.toArray)
            |> Array.toList

        Assert.True(expectedScenarioCount > 0)
        Assert.Equal(expectedScenarioCount, scenarioCount)
        Assert.Empty(BindingCompliance.validate (BindingCompliance.patterns assembly) steps)

    [<Fact>]
    member _.``embedded features exactly match the recursive canonical corpus``() =
        let assembly = Assembly.GetExecutingAssembly()

        let featureRoot =
            Path.GetFullPath(Path.Combine(__SOURCE_DIRECTORY__, "../../../../specs/apps/badakmini/cli/behaviours"))

        let diskNames =
            Directory.EnumerateFiles(featureRoot, "*.feature", SearchOption.AllDirectories)
            |> Seq.map (fun path ->
                Path.GetRelativePath(featureRoot, path).Replace(Path.DirectorySeparatorChar, '.')
                |> fun relative -> FeatureCatalog.ResourcePrefix + relative)
            |> Seq.sort
            |> Seq.toArray

        Assert.Equal<string array>(diskNames, FeatureCatalog.resourceNames assembly)

    [<Fact>]
    member _.``adapter implements the complete behavior driver contract``() =
        let contractType = typeof<IBehaviourDriver>

        let adapterTypes =
            Assembly.GetExecutingAssembly().GetTypes()
            |> Array.filter (fun reflectedType ->
                not reflectedType.IsAbstract
                && not reflectedType.IsInterface
                && contractType.IsAssignableFrom reflectedType)

        let adapterType = Assert.Single adapterTypes
        let mapping = adapterType.GetInterfaceMap contractType
        let expected = contractType.GetMethods() |> Array.map _.Name
        let actual = mapping.InterfaceMethods |> Array.map _.Name
        Assert.Empty(DriverCompliance.missingMembers expected actual)

    [<Fact>]
    member _.``undefined binding is rejected``() =
        let errors =
            BindingCompliance.validate
                []
                [ { Kind = WhenBinding
                    Text = "an undefined action" } ]

        Assert.Contains(errors, fun error -> error.Contains("Undefined behavior step"))

    [<Fact>]
    member _.``ambiguous bindings are rejected``() =
        let bindings: BindingPattern list =
            [ { Kind = ThenBinding
                Pattern = "the result is (.*)"
                MethodName = "first" }
              { Kind = ThenBinding
                Pattern = "the result is good"
                MethodName = "second" } ]

        let errors =
            BindingCompliance.validate
                bindings
                [ { Kind = ThenBinding
                    Text = "the result is good" } ]

        Assert.Contains(errors, fun error -> error.Contains("Ambiguous behavior step"))

    [<Fact>]
    member _.``unused binding is rejected``() =
        let bindings: BindingPattern list =
            [ { Kind = GivenBinding
                Pattern = "a used precondition"
                MethodName = "used" }
              { Kind = GivenBinding
                Pattern = "an unused precondition"
                MethodName = "unused" } ]

        let errors =
            BindingCompliance.validate
                bindings
                [ { Kind = GivenBinding
                    Text = "a used precondition" } ]

        Assert.Contains(errors, fun error -> error.Contains("Unused behavior binding: unused"))

    [<Fact>]
    member _.``incomplete driver contract is rejected``() =
        let missing = DriverCompliance.missingMembers [ "Write"; "InvokeCli" ] [ "Write" ]
        Assert.Single missing |> ignore
        Assert.Contains("InvokeCli", missing)
