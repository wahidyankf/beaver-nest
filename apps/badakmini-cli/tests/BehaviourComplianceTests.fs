namespace Badakmini.Cli.BehaviourTests

open System.Reflection
open global.Xunit

type FeatureComplianceTests() =
    let validFeature boundaryTag =
        $"{boundaryTag}\nFeature: Compliance example\n\n  Scenario: Observable behavior\n    Given a precondition\n    When an action occurs\n    Then an outcome is observed"

    let assertErrorContains (expected: string) source =
        match FeatureCompliance.validate "example.feature" source with
        | Error errors -> Assert.Contains(errors, fun error -> error.Contains expected)
        | Ok boundary -> failwithf "Expected compliance failure containing '%s', got %A" expected boundary

    [<Fact>]
    member _.``pure feature is classified``() =
        Assert.Equal(Ok Pure, FeatureCompliance.validate "example.feature" (validFeature "@pure"))

    [<Fact>]
    member _.``process-global feature is classified``() =
        Assert.Equal(Ok ProcessGlobal, FeatureCompliance.validate "example.feature" (validFeature "@process_global"))

    [<Fact>]
    member _.``unrelated feature and scenario tags remain available``() =
        let source =
            "@documentation @pure\nFeature: Compliance example\n\n  @smoke\n  Scenario: Tagged behavior\n    Given a precondition\n    When an action occurs\n    Then an outcome is observed"

        Assert.Equal(Ok Pure, FeatureCompliance.validate "example.feature" source)

    [<Fact>]
    member _.``feature without an execution boundary is rejected``() =
        validFeature ""
        |> assertErrorContains "exactly one feature-level execution boundary"

    [<Fact>]
    member _.``feature with conflicting execution boundaries is rejected``() =
        validFeature "@pure @process_global"
        |> assertErrorContains "exactly one feature-level execution boundary"

    [<Fact>]
    member _.``scenario-level execution boundary is rejected``() =
        "@pure\nFeature: Compliance example\n\n  @process_global\n  Scenario: Invalid override\n    Given a precondition\n    When an action occurs\n    Then an outcome is observed"
        |> assertErrorContains "execution boundary tags are allowed only before Feature:"

    [<Fact>]
    member _.``feature without scenarios is rejected``() =
        "@pure\nFeature: Empty feature" |> assertErrorContains "at least one scenario"

    [<Fact>]
    member _.``scenario without When is rejected``() =
        "@pure\nFeature: Compliance example\n\n  Scenario: Missing action\n    Given a precondition\n    Then an outcome is observed"
        |> assertErrorContains "requires a When step"

    [<Fact>]
    member _.``scenario without Then is rejected``() =
        "@pure\nFeature: Compliance example\n\n  Scenario: Missing outcome\n    Given a precondition\n    When an action occurs"
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
