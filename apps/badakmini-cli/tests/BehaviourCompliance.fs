namespace Badakmini.Cli.BehaviourTests

open System
open System.IO
open System.Reflection
open System.Text.RegularExpressions
open TickSpec.Xunit

type ExecutionBoundary =
    | Pure
    | ProcessGlobal

module FeatureCompliance =
    let private startsWith (prefix: string) (value: string) =
        value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)

    let private boundaryTags (line: string) =
        if line.TrimStart().StartsWith('@') then
            Regex.Matches(line, @"@(\w+)")
            |> Seq.cast<Match>
            |> Seq.map _.Groups[1].Value
            |> Seq.choose (function
                | "pure" -> Some Pure
                | "process_global" -> Some ProcessGlobal
                | _ -> None)
            |> Seq.toList
        else
            []

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

    let validate (resourceName: string) (source: string) : Result<ExecutionBoundary, string list> =
        let lines = source.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n')

        let featureIndex =
            lines |> Array.tryFindIndex (fun line -> startsWith "Feature:" (line.Trim()))

        let featureTags, misplacedBoundaryTags =
            match featureIndex with
            | None -> [], []
            | Some index ->
                lines[.. index - 1] |> Array.toList |> List.collect boundaryTags,
                lines[index + 1 ..] |> Array.toList |> List.collect boundaryTags

        let errors = ResizeArray<string>()

        if featureTags.Length <> 1 then
            errors.Add(
                $"{resourceName}: expected exactly one feature-level execution boundary tag (@pure or @process_global)."
            )

        if not misplacedBoundaryTags.IsEmpty then
            errors.Add($"{resourceName}: execution boundary tags are allowed only before Feature:.")

        match featureIndex with
        | None -> errors.Add($"{resourceName}: missing Feature: declaration.")
        | Some _ -> ()

        scenarioErrors resourceName lines |> List.iter errors.Add

        if errors.Count > 0 then
            Error(errors |> Seq.toList)
        else
            Ok featureTags.Head

type LoadedFeature =
    { ResourceName: string
      Boundary: ExecutionBoundary
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

    let private readResource (assembly: Assembly) resourceName =
        use stream = assembly.GetManifestResourceStream resourceName

        if isNull stream then
            invalidOp $"Embedded behavior resource '{resourceName}' could not be opened."

        use reader = new StreamReader(stream)
        reader.ReadToEnd()

    let load (assembly: Assembly) (source: AssemblyStepDefinitionsSource) =
        let resources = resourceNames assembly

        if resources.Length = 0 then
            invalidOp $"No embedded behavior resources were found below '{ResourcePrefix}'."

        resources
        |> Array.map (fun resourceName ->
            let boundary =
                match readResource assembly resourceName |> FeatureCompliance.validate resourceName with
                | Ok boundary -> boundary
                | Error errors -> errors |> String.concat Environment.NewLine |> invalidOp

            { ResourceName = resourceName
              Boundary = boundary
              Scenarios = source.ScenariosFromEmbeddedResource resourceName |> Seq.toArray })
