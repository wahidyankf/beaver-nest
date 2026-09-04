namespace Badakmini.Cli.BehaviourTests

open System
open System.IO
open System.Reflection
open System.Text.RegularExpressions
open TickSpec
open TickSpec.Xunit

module FeatureCompliance =
    let private exemptionTags = set [ "integration-exempt"; "e2e-exempt" ]

    let private forbiddenTags =
        set [ "unit-exempt"; "no-unit"; "no-integration"; "no-e2e" ]

    let private exemptionComment =
        Regex("^# Exemption\\((integration|e2e)\\): (.+); alternative-proof: (.+)$", RegexOptions.CultureInvariant)

    let private invalidReason =
        Regex(
            "\\b(?:hard|slow|flaky|not yet implemented|todo)\\b",
            RegexOptions.IgnoreCase ||| RegexOptions.CultureInvariant
        )

    let private startsWith (prefix: string) (value: string) =
        value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)

    let private scenarioErrors resourceName (lines: string array) =
        let errors = ResizeArray<string>()
        let mutable scenarioCount = 0
        let mutable currentScenario: string option = None
        let mutable hasWhen = false
        let mutable hasThen = false
        let mutable insideDocString = false

        let finishScenario () =
            match currentScenario with
            | None -> ()
            | Some scenario ->
                if not hasWhen then
                    errors.Add($"{resourceName}: {scenario} requires a When step.")

                if not hasThen then
                    errors.Add($"{resourceName}: {scenario} requires a Then step.")

        for line in lines do
            let trimmed = line.Trim()

            if trimmed = "\"\"\"" then
                insideDocString <- not insideDocString
            elif not insideDocString then
                if startsWith "Scenario" trimmed || startsWith "Story" trimmed then
                    finishScenario ()
                    scenarioCount <- scenarioCount + 1
                    currentScenario <- Some trimmed
                    hasWhen <- false
                    hasThen <- false
                elif currentScenario.IsSome && startsWith "When " trimmed then
                    hasWhen <- true
                elif currentScenario.IsSome && startsWith "Then " trimmed then
                    hasThen <- true

        finishScenario ()

        if scenarioCount = 0 then
            errors.Add($"{resourceName}: feature must contain at least one scenario.")

        errors |> Seq.toList

    let private exemptionErrors resourceName (lines: string array) =
        let errors = ResizeArray<string>()
        let mutable pending: (int * string) list = []

        let finishPending declaration lineNumber =
            let exemptions =
                pending |> List.filter (fun (_, name) -> exemptionTags.Contains name)

            if not exemptions.IsEmpty then
                if not (startsWith "Scenario" declaration || startsWith "Story" declaration) then
                    errors.Add(
                        $"{resourceName}:{lineNumber}: exemption tags may only annotate a Scenario or Scenario Outline."
                    )

                if exemptions |> List.map snd |> Set.ofList |> Set.count > 1 then
                    errors.Add(
                        $"{resourceName}:{lineNumber}: a scenario cannot be both @integration-exempt and @e2e-exempt."
                    )

                for tagLine, tagName in exemptions do
                    let comment = if tagLine >= 2 then lines[tagLine - 2].Trim() else ""
                    let matched = exemptionComment.Match comment
                    let layer = tagName.Replace("-exempt", "")

                    if not matched.Success || matched.Groups[1].Value <> layer then
                        errors.Add(
                            $"{resourceName}:{tagLine}: @{tagName} requires the immediately preceding comment '# Exemption({layer}): <reason>; alternative-proof: <Nx target/scenario>'."
                        )
                    else
                        if invalidReason.IsMatch matched.Groups[2].Value then
                            errors.Add(
                                $"{resourceName}:{tagLine}: an exemption cannot be justified by difficulty, speed, flakiness, or missing implementation."
                            )

                        if
                            not (
                                Regex.IsMatch(
                                    matched.Groups[3].Value,
                                    "^[a-z0-9-]+:test(?::[a-z0-9-]+)*\\s+/\\s+\\S",
                                    RegexOptions.IgnoreCase ||| RegexOptions.CultureInvariant
                                )
                            )
                        then
                            errors.Add(
                                $"{resourceName}:{tagLine}: alternative-proof must name an Nx test target and scenario after ' / '."
                            )

            pending <- []

        for index, line in lines |> Array.indexed do
            let trimmed = line.Trim()
            let lineNumber = index + 1

            if trimmed.StartsWith("@", StringComparison.Ordinal) then
                let names =
                    trimmed.Split([| ' '; '\t' |], StringSplitOptions.RemoveEmptyEntries)
                    |> Array.filter (fun part -> part.StartsWith("@", StringComparison.Ordinal))
                    |> Array.map (fun part -> part.Substring 1)

                for name in names do
                    if forbiddenTags.Contains name then
                        errors.Add(
                            $"{resourceName}:{lineNumber}: @{name} is forbidden; unit has no exemption and higher layers use @integration-exempt or @e2e-exempt."
                        )

                    pending <- pending @ [ lineNumber, name ]
            elif
                [ "Feature:"
                  "Rule:"
                  "Background:"
                  "Scenario"
                  "Story:"
                  "Examples:"
                  "Example:" ]
                |> List.exists (fun prefix -> startsWith prefix trimmed)
            then
                finishPending trimmed lineNumber
            elif
                trimmed <> ""
                && not (trimmed.StartsWith("#", StringComparison.Ordinal))
                && not pending.IsEmpty
            then
                errors.Add($"{resourceName}:{lineNumber}: tags must be followed by their Gherkin declaration.")
                pending <- []

        if not pending.IsEmpty then
            errors.Add($"{resourceName}: dangling tags are not attached to a scenario.")

        errors |> Seq.toList

    let validate (resourceName: string) (source: string) : Result<unit, string list> =
        let lines = source.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n')

        let featureIndex =
            lines |> Array.tryFindIndex (fun line -> startsWith "Feature:" (line.Trim()))

        let errors = ResizeArray<string>()

        match featureIndex with
        | None -> errors.Add($"{resourceName}: missing Feature: declaration.")
        | Some _ -> ()

        scenarioErrors resourceName lines |> List.iter errors.Add
        exemptionErrors resourceName lines |> List.iter errors.Add

        if errors.Count > 0 then
            Error(errors |> Seq.toList)
        else
            Ok()

type LoadedFeature =
    { ResourceName: string
      Scenarios: XunitSerializableScenario array }

module FeatureCatalog =
    [<Literal>]
    let ResourcePrefix = "Badakmini.Cli.Specs."

    let resourceNames (assembly: Assembly) =
        assembly.GetManifestResourceNames()
        |> Array.filter (fun name ->
            name.StartsWith(ResourcePrefix, StringComparison.Ordinal)
            && name.EndsWith(".feature", StringComparison.Ordinal))
        |> Array.sort

    let readResource (assembly: Assembly) resourceName =
        use stream = assembly.GetManifestResourceStream resourceName

        if isNull stream then
            invalidOp $"Embedded behaviour resource '{resourceName}' could not be opened."

        use reader = new StreamReader(stream)
        reader.ReadToEnd()

    let load (assembly: Assembly) (source: AssemblyStepDefinitionsSource) =
        let resources = resourceNames assembly

        if resources.Length = 0 then
            invalidOp $"No embedded behaviour resources were found below '{ResourcePrefix}'."

        resources
        |> Array.map (fun resourceName ->
            match readResource assembly resourceName |> FeatureCompliance.validate resourceName with
            | Ok() ->
                { ResourceName = resourceName
                  Scenarios = source.ScenariosFromEmbeddedResource resourceName |> Seq.toArray }
            | Error errors -> errors |> String.concat Environment.NewLine |> invalidOp)

type BindingKind =
    | GivenBinding
    | WhenBinding
    | ThenBinding

type BindingPattern =
    { Kind: BindingKind
      Pattern: string
      MethodName: string }

type ScenarioStep = { Kind: BindingKind; Text: string }

module BindingCompliance =
    let patterns (assembly: Assembly) =
        let pattern (attribute: StepAttribute) methodName =
            if String.IsNullOrEmpty attribute.Step then
                methodName
            else
                attribute.Step

        assembly.GetTypes()
        |> Array.collect (fun reflectedType ->
            reflectedType.GetMethods(BindingFlags.Public ||| BindingFlags.NonPublic ||| BindingFlags.Static)
            |> Array.collect (fun methodInfo ->
                methodInfo.GetCustomAttributes(false)
                |> Array.choose (fun attribute ->
                    match attribute with
                    | :? GivenAttribute as step ->
                        Some
                            { Kind = GivenBinding
                              Pattern = pattern step methodInfo.Name
                              MethodName = methodInfo.Name }
                    | :? WhenAttribute as step ->
                        Some
                            { Kind = WhenBinding
                              Pattern = pattern step methodInfo.Name
                              MethodName = methodInfo.Name }
                    | :? ThenAttribute as step ->
                        Some
                            { Kind = ThenBinding
                              Pattern = pattern step methodInfo.Name
                              MethodName = methodInfo.Name }
                    | _ -> None)))
        |> Array.toList

    let steps (source: string) : ScenarioStep list =
        FeatureParser.parseFeature (source.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        |> _.Scenarios
        |> Array.collect _.Steps
        |> Array.map (fun (stepType, _) ->
            match stepType with
            | GivenStep text -> { Kind = GivenBinding; Text = text }
            | WhenStep text -> { Kind = WhenBinding; Text = text }
            | ThenStep text -> { Kind = ThenBinding; Text = text })
        |> Array.toList

    let validate (bindings: BindingPattern list) (scenarioSteps: ScenarioStep list) =
        let used = Collections.Generic.HashSet<BindingPattern>()
        let errors = ResizeArray<string>()

        for step in scenarioSteps do
            let matches =
                bindings
                |> List.filter (fun binding ->
                    binding.Kind = step.Kind
                    && Regex.IsMatch(step.Text, $"^(?:{binding.Pattern})$", RegexOptions.CultureInvariant))

            match matches with
            | [ binding ] -> used.Add binding |> ignore
            | [] -> errors.Add($"Undefined behaviour step: {step.Text}")
            | _ -> errors.Add($"Ambiguous behaviour step: {step.Text}")

        for binding in bindings do
            if not (used.Contains binding) then
                errors.Add($"Unused behaviour binding: {binding.MethodName} / {binding.Pattern}")

        errors |> Seq.toList

module DriverCompliance =
    let missingMembers expectedMembers implementationMembers =
        Set.difference (Set.ofSeq expectedMembers) (Set.ofSeq implementationMembers)
