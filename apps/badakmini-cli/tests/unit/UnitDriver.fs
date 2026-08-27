module Badakmini.Cli.BehaviourDriverFactory

open System
open System.Collections.Generic
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
    | InvalidMarkdownLink issue ->
        { Kind = "invalid Markdown link"
          Path = issue.Path
          RelatedPath = None
          Target = Some issue.Target
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
    | MermaidLegibilityViolation issue ->
        { Kind = "Mermaid legibility"
          Path = issue.Path
          RelatedPath = None
          Target = None
          WordCount = None
          Line = Some issue.Line
          Diagnostic = Governance.formatViolation violation }

type private MemoryRepository() =
    let root =
        Path.GetFullPath(Path.Combine(Path.DirectorySeparatorChar.ToString(), $"badakmini-unit-{Guid.NewGuid():N}"))

    let files = Dictionary<string, string>(StringComparer.Ordinal)
    let directories = HashSet<string>(StringComparer.Ordinal)
    let locked = HashSet<string>(StringComparer.Ordinal)

    let normalize path = Path.GetFullPath path

    let directChildren (entries: seq<string>) directory =
        let directory = normalize directory

        entries
        |> Seq.filter (fun path ->
            let parent = Path.GetDirectoryName path

            not (isNull parent)
            && String.Equals(normalize parent, directory, StringComparison.Ordinal))
        |> Seq.sort

    let addDirectories (path: string) =
        let rec add (directory: string) =
            if not (String.IsNullOrEmpty directory) && directories.Add(normalize directory) then
                add (Path.GetDirectoryName directory)

        add (Path.GetDirectoryName path)

    do directories.Add root |> ignore

    let fileSystem =
        { FileExists = fun path -> files.ContainsKey(normalize path)
          DirectoryExists = fun path -> directories.Contains(normalize path)
          ReadAllText =
            fun path ->
                let path = normalize path

                if locked.Contains path then
                    raise (IOException($"File is locked: {path}"))

                match files.TryGetValue path with
                | true, content -> content
                | false, _ -> raise (FileNotFoundException("File does not exist.", path))
          EnumerateFiles = fun directory -> directChildren files.Keys directory
          EnumerateDirectories = fun directory -> directChildren directories directory
          EnumerateFileSystemEntries =
            fun directory -> Seq.append (directChildren files.Keys directory) (directChildren directories directory)
          GetAttributes = fun _ -> FileAttributes.Normal
          CurrentDirectory = fun () -> root }

    member _.Root = root
    member _.FileSystem = fileSystem

    member _.Write(relativePath, content) =
        let path = normalize (Path.Combine(root, relativePath))
        addDirectories path
        files[path] <- content

    member _.Lock(relativePath) =
        locked.Add(normalize (Path.Combine(root, relativePath))) |> ignore

type private UnitDriver() =
    let repository = MemoryRepository()

    let capture arguments =
        use output = new StringWriter()
        use error = new StringWriter()

        let runtime =
            { FileSystem = repository.FileSystem
              Output = output
              Error = error }

        { ExitCode = Cli.invokeWith runtime arguments
          StandardOutput = output.ToString()
          StandardError = error.ToString() }

    let commandArguments validator =
        match validator with
        | "word-budget" -> [| "governance"; "word-budget"; "validate" |]
        | "directory-map" -> [| "governance"; "directory-map"; "validate" |]
        | "links" -> [| "md"; "links"; "validate" |]
        | "mermaid" -> [| "md"; "mermaid"; "validate" |]
        | _ -> failwithf "Unknown validator '%s'." validator

    let relativeDirectory location =
        match location with
        | "empty path" -> ""
        | "absolute repository root" -> repository.Root
        | "outside repository" -> "../outside"
        | _ -> failwithf "Unknown invalid directory location '%s'." location

    interface IBehaviourDriver with
        member _.Root = repository.Root
        member _.Write(relativePath, content) = repository.Write(relativePath, content)
        member _.Lock(relativePath) = repository.Lock relativePath

        member _.CountWords(relativePath) =
            repository.FileSystem.ReadAllText(Path.Combine(repository.Root, relativePath))
            |> Governance.countWords

        member _.ScanGovernedMarkdown() =
            Governance.scanRepositoryWith repository.FileSystem repository.Root
            |> List.map _.Path

        member _.FindWordLimitViolations() =
            let files = Governance.scanRepositoryWith repository.FileSystem repository.Root

            files |> List.map _.Path,
            files
            |> Governance.findViolations
            |> List.map (WordLimitExceeded >> violationView)

        member _.InspectWordBudget() =
            let inspection =
                Governance.inspectWordBudgetWith repository.FileSystem repository.Root

            inspection.MarkdownFiles |> List.map _.Path, inspection.Violations |> List.map violationView

        member _.InspectDirectoryMaps() =
            let inspection =
                Governance.inspectDirectoryMapsWith repository.FileSystem repository.Root

            inspection.DirectoryCount, inspection.Violations |> List.map violationView

        member _.InspectDirectoryMapsAtInvalidLocation(location) =
            try
                Governance.inspectDirectoryMapsAtWith repository.FileSystem repository.Root (relativeDirectory location)
                |> ignore

                false
            with :? ArgumentException ->
                true

        member _.InspectMermaidAccessibility() =
            let inspection =
                Governance.inspectMermaidAccessibilityWith repository.FileSystem repository.Root

            inspection.DiagramCount, inspection.Violations |> List.map violationView

        member _.RunValidator(validator) =
            Array.append (commandArguments validator) [| "--root"; repository.Root |]
            |> capture

        member _.RunDirectoryMapValidator(directory) =
            [| "governance"
               "directory-map"
               "validate"
               "--directory"
               directory
               "--root"
               repository.Root |]
            |> capture

        member _.InvokeCli(arguments) = capture arguments
        member _.InvokeCliFromRepository(arguments) = capture arguments
        member _.Dispose() = ()

let create () : IBehaviourDriver = new UnitDriver()
