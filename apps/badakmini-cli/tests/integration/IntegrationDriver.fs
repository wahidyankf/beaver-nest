module Badakmini.Cli.BehaviourDriverFactory

open System
open System.IO
open Badakmini.Cli
open Badakmini.Cli.BehaviourTests

let private violationView violation =
    match violation with
    | WordLimitExceeded file ->
        { Kind = "word limit exceeded"
          Path = file.Path
          RelatedPath = None
          Target = None
          WordCount = Some file.WordCount
          Line = None
          Diagnostic = Governance.formatViolation violation }
    | MissingReadme path ->
        { Kind = "missing README"
          Path = path
          RelatedPath = None
          Target = None
          WordCount = None
          Line = None
          Diagnostic = Governance.formatViolation violation }
    | MissingDirectoryMap path ->
        { Kind = "missing directory map"
          Path = path
          RelatedPath = None
          Target = None
          WordCount = None
          Line = None
          Diagnostic = Governance.formatViolation violation }
    | MissingMapEntry(path, sibling) ->
        { Kind = "missing map entry"
          Path = path
          RelatedPath = Some sibling
          Target = None
          WordCount = None
          Line = None
          Diagnostic = Governance.formatViolation violation }
    | InvalidMapEntry(path, target) ->
        { Kind = "invalid map entry"
          Path = path
          RelatedPath = None
          Target = Some target
          WordCount = None
          Line = None
          Diagnostic = Governance.formatViolation violation }
    | MermaidAccessibilityViolation issue ->
        { Kind = "Mermaid accessibility"
          Path = issue.Path
          RelatedPath = None
          Target = None
          WordCount = None
          Line = Some issue.Line
          Diagnostic = Governance.formatViolation violation }

type private IntegrationDriver() =
    let root =
        Path.Combine(Path.GetTempPath(), $"badakmini-integration-{Guid.NewGuid():N}")

    let resources = ResizeArray<IDisposable>()

    do Directory.CreateDirectory root |> ignore

    let capture currentDirectory arguments =
        use output = new StringWriter()
        use error = new StringWriter()

        let runtime =
            { FileSystem =
                { RepositoryFileSystem.system with
                    CurrentDirectory = fun () -> currentDirectory }
              Output = output
              Error = error }

        { ExitCode = Cli.invokeWith runtime arguments
          StandardOutput = output.ToString()
          StandardError = error.ToString() }

    let commandArguments validator =
        match validator with
        | "word-budget" -> [| "governance"; "word-budget"; "validate" |]
        | "directory-map" -> [| "governance"; "directory-map"; "validate" |]
        | "mermaid" -> [| "md"; "mermaid"; "validate" |]
        | _ -> failwithf "Unknown validator '%s'." validator

    let relativeDirectory location =
        match location with
        | "empty path" -> ""
        | "absolute repository root" -> root
        | "outside repository" -> "../outside"
        | _ -> failwithf "Unknown invalid directory location '%s'." location

    interface IBehaviourDriver with
        member _.Root = root

        member _.Write(relativePath, content) =
            let path = Path.Combine(root, relativePath)
            let directory = Path.GetDirectoryName path

            if not (String.IsNullOrEmpty directory) then
                Directory.CreateDirectory directory |> ignore

            File.WriteAllText(path, content)

        member _.Lock(relativePath) =
            let stream =
                new FileStream(Path.Combine(root, relativePath), FileMode.Open, FileAccess.Read, FileShare.None)

            resources.Add stream

        member _.CountWords(relativePath) =
            File.ReadAllText(Path.Combine(root, relativePath)) |> Governance.countWords

        member _.ScanGovernedMarkdown() =
            Governance.scanRepositoryWith RepositoryFileSystem.system root
            |> List.map _.Path

        member _.FindWordLimitViolations() =
            let files = Governance.scanRepositoryWith RepositoryFileSystem.system root

            files |> List.map _.Path,
            files
            |> Governance.findViolations
            |> List.map (WordLimitExceeded >> violationView)

        member _.InspectWordBudget() =
            let inspection = Governance.inspectWordBudgetWith RepositoryFileSystem.system root
            inspection.MarkdownFiles |> List.map _.Path, inspection.Violations |> List.map violationView

        member _.InspectDirectoryMaps() =
            let inspection =
                Governance.inspectDirectoryMapsWith RepositoryFileSystem.system root

            inspection.DirectoryCount, inspection.Violations |> List.map violationView

        member _.InspectDirectoryMapsAtInvalidLocation(location) =
            try
                Governance.inspectDirectoryMapsAtWith RepositoryFileSystem.system root (relativeDirectory location)
                |> ignore

                false
            with :? ArgumentException ->
                true

        member _.InspectMermaidAccessibility() =
            let inspection =
                Governance.inspectMermaidAccessibilityWith RepositoryFileSystem.system root

            inspection.DiagramCount, inspection.Violations |> List.map violationView

        member _.RunValidator(validator) =
            Array.append (commandArguments validator) [| "--root"; root |] |> capture root

        member _.RunDirectoryMapValidator(directory) =
            [| "governance"
               "directory-map"
               "validate"
               "--directory"
               directory
               "--root"
               root |]
            |> capture root

        member _.InvokeCli(arguments) = capture root arguments
        member _.InvokeCliFromRepository(arguments) = capture root arguments

        member _.Dispose() =
            for resource in Seq.rev resources do
                resource.Dispose()

            if Directory.Exists root then
                Directory.Delete(root, true)

let create () : IBehaviourDriver = new IntegrationDriver()
