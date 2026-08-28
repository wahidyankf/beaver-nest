module Badakmini.Cli.BehaviourDriverFactory

open System
open System.Diagnostics
open System.IO
open System.Text.Json
open Badakmini.Cli.BehaviourTests

let private optionText (element: JsonElement) (property: string) =
    match element.TryGetProperty property with
    | true, value when value.ValueKind <> JsonValueKind.Null -> Some(value.GetString())
    | _ -> None

let private optionInt (element: JsonElement) (property: string) =
    match element.TryGetProperty property with
    | true, value when value.ValueKind <> JsonValueKind.Null -> Some(value.GetInt32())
    | _ -> None

let private violationView (element: JsonElement) =
    let kind = element.GetProperty("kind").GetString()

    { Kind =
        match kind with
        | "word-limit-exceeded" -> "word limit exceeded"
        | "missing-readme" -> "missing README"
        | "missing-directory-map" -> "missing directory map"
        | "missing-map-entry" -> "missing map entry"
        | "invalid-map-entry" -> "invalid map entry"
        | "invalid-markdown-link" -> "invalid Markdown link"
        | "mermaid-accessibility" -> "Mermaid accessibility"
        | "mermaid-legibility" -> "Mermaid legibility"
        | unknown -> failwithf "Unknown CLI violation kind '%s'." unknown
      Path = element.GetProperty("path").GetString()
      RelatedPath = optionText element "relatedPath"
      Target = optionText element "target"
      WordCount = optionInt element "wordCount"
      Line = optionInt element "line"
      Diagnostic = element.GetProperty("message").GetString() }

type private E2eDriver() =
    let root = Path.Combine(Path.GetTempPath(), $"badakmini-e2e-{Guid.NewGuid():N}")
    let resources = ResizeArray<IDisposable>()

    let cliDll =
        match Environment.GetEnvironmentVariable "BADAKMINI_CLI_DLL" with
        | value when not (String.IsNullOrWhiteSpace value) -> Path.GetFullPath value
        | _ ->
            Path.GetFullPath(
                Path.Combine(__SOURCE_DIRECTORY__, "../badakmini-cli/bin/Release/net10.0/Badakmini.Cli.dll")
            )

    do
        Directory.CreateDirectory root |> ignore

        if not (File.Exists cliDll) then
            invalidOp $"Built badakmini-cli executable was not found at '{cliDll}'."

    let snapshot () =
        Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
        |> Seq.filter (fun path -> not (File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)))
        |> Seq.map (fun path ->
            Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/'), File.ReadAllText path)
        |> Seq.sortBy fst
        |> Seq.toList

    let run workingDirectory arguments =
        let startInfo = ProcessStartInfo("dotnet")
        startInfo.ArgumentList.Add cliDll

        for argument in arguments do
            startInfo.ArgumentList.Add argument

        startInfo.WorkingDirectory <- workingDirectory
        startInfo.UseShellExecute <- false
        startInfo.RedirectStandardOutput <- true
        startInfo.RedirectStandardError <- true

        use childProcess = new Process(StartInfo = startInfo)

        if not (childProcess.Start()) then
            invalidOp "Failed to start badakmini-cli."

        let output = childProcess.StandardOutput.ReadToEndAsync()
        let error = childProcess.StandardError.ReadToEndAsync()

        if not (childProcess.WaitForExit 30_000) then
            childProcess.Kill true
            failwith "badakmini-cli did not exit within 30 seconds."

        { ExitCode = childProcess.ExitCode
          StandardOutput = output.GetAwaiter().GetResult()
          StandardError = error.GetAwaiter().GetResult() }

    let runAtRoot arguments = run root arguments

    let runJson arguments =
        let result =
            Array.append arguments [| "--root"; root; "--format"; "json" |] |> runAtRoot

        if result.ExitCode = 2 then
            failwithf "badakmini-cli JSON inspection failed: %s" result.StandardError

        JsonDocument.Parse(result.StandardOutput)

    let violations (document: JsonDocument) =
        document.RootElement.GetProperty("violations").EnumerateArray()
        |> Seq.map violationView
        |> Seq.toList

    let commandArguments validator =
        match validator with
        | "word-budget" -> [| "governance"; "word-budget"; "validate" |]
        | "directory-map" -> [| "governance"; "directory-map"; "validate" |]
        | "links" -> [| "md"; "links"; "validate" |]
        | "mermaid" -> [| "md"; "mermaid"; "validate" |]
        | "harness-contract" -> [| "governance"; "harness-contract"; "validate" |]
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

        member _.Delete(relativePath) =
            let path = Path.Combine(root, relativePath)

            if File.Exists path then
                File.Delete path
            elif Directory.Exists path then
                Directory.Delete(path, true)

        member _.Link(relativePath, target) =
            let path = Path.Combine(root, relativePath)
            let directory = Path.GetDirectoryName path

            if not (String.IsNullOrEmpty directory) then
                Directory.CreateDirectory directory |> ignore

            Directory.CreateSymbolicLink(path, Path.Combine(root, target)) |> ignore

        member _.Lock(relativePath) =
            let stream =
                new FileStream(Path.Combine(root, relativePath), FileMode.Open, FileAccess.Read, FileShare.None)

            resources.Add stream

        member _.Snapshot() = snapshot ()

        member _.CountWords(relativePath) =
            use document = runJson [| "md"; "word-count"; "inspect"; "--file"; relativePath |]
            document.RootElement.GetProperty("wordCount").GetInt32()

        member _.ScanGovernedMarkdown() =
            use document = runJson [| "governance"; "word-budget"; "validate" |]

            document.RootElement.GetProperty("markdownFiles").EnumerateArray()
            |> Seq.map (fun file -> file.GetProperty("path").GetString())
            |> Seq.toList

        member _.FindWordLimitViolations() =
            use document = runJson [| "governance"; "word-budget"; "validate" |]

            let paths =
                document.RootElement.GetProperty("markdownFiles").EnumerateArray()
                |> Seq.map (fun file -> file.GetProperty("path").GetString())
                |> Seq.toList

            paths, violations document

        member _.InspectWordBudget() =
            use document = runJson [| "governance"; "word-budget"; "validate" |]

            let paths =
                document.RootElement.GetProperty("markdownFiles").EnumerateArray()
                |> Seq.map (fun file -> file.GetProperty("path").GetString())
                |> Seq.toList

            paths, violations document

        member _.InspectDirectoryMaps() =
            use document = runJson [| "governance"; "directory-map"; "validate" |]
            document.RootElement.GetProperty("directoryCount").GetInt32(), violations document

        member _.InspectDirectoryMapsAtInvalidLocation(location) =
            [| "governance"
               "directory-map"
               "validate"
               "--directory"
               relativeDirectory location
               "--root"
               root
               "--format"
               "json" |]
            |> runAtRoot
            |> _.ExitCode
            |> (=) 2

        member _.InspectMermaidAccessibility() =
            use document = runJson [| "md"; "mermaid"; "validate" |]
            document.RootElement.GetProperty("diagramCount").GetInt32(), violations document

        member _.InspectHarnessContract() =
            [| "governance"
               "harness-contract"
               "validate"
               "--root"
               root
               "--format"
               "json" |]
            |> runAtRoot

        member _.RunValidator(validator) =
            Array.append (commandArguments validator) [| "--root"; root |] |> runAtRoot

        member _.RunDirectoryMapValidator(directory) =
            [| "governance"
               "directory-map"
               "validate"
               "--directory"
               directory
               "--root"
               root |]
            |> runAtRoot

        member _.InvokeCli(arguments) = runAtRoot arguments
        member _.InvokeCliFromRepository(arguments) = run root arguments

        member _.Dispose() =
            for resource in Seq.rev resources do
                resource.Dispose()

            if Directory.Exists root then
                Directory.Delete(root, true)

let create () : IBehaviourDriver = new E2eDriver()
