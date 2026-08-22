module Badakmini.Cli.BehaviourSupport

open System
open System.Collections.Generic
open System.IO
open TickSpec
open global.Xunit
open Badakmini.Cli

type ScenarioContext() =
    let root = Path.Combine(Path.GetTempPath(), $"badakmini-cli-{Guid.NewGuid():N}")
    let resources = ResizeArray<IDisposable>()
    let mutable markdownFiles: MarkdownFile list = []
    let mutable violations: GovernanceViolation list = []
    let mutable directoryCount: int option = None
    let mutable diagramCount: int option = None
    let mutable wordCount: int option = None
    let mutable exceptionRaised: exn option = None
    let mutable exitCode: int option = None
    let mutable standardOutput = ""
    let mutable standardError = ""

    do Directory.CreateDirectory(root) |> ignore

    member _.Root = root

    member _.MarkdownFiles
        with get () = markdownFiles
        and set value = markdownFiles <- value

    member _.Violations
        with get () = violations
        and set value = violations <- value

    member _.DirectoryCount
        with get () = directoryCount
        and set value = directoryCount <- value

    member _.DiagramCount
        with get () = diagramCount
        and set value = diagramCount <- value

    member _.WordCount
        with get () = wordCount
        and set value = wordCount <- value

    member _.ExceptionRaised
        with get () = exceptionRaised
        and set value = exceptionRaised <- value

    member _.ExitCode
        with get () = exitCode
        and set value = exitCode <- value

    member _.StandardOutput
        with get () = standardOutput
        and set value = standardOutput <- value

    member _.StandardError
        with get () = standardError
        and set value = standardError <- value

    member _.Write(relativePath: string, content: string) =
        let path = Path.Combine(root, relativePath)
        let directory = Path.GetDirectoryName path

        if not (String.IsNullOrEmpty directory) then
            Directory.CreateDirectory(directory) |> ignore

        File.WriteAllText(path, content)

    member _.Lock(relativePath: string) =
        let stream =
            new FileStream(Path.Combine(root, relativePath), FileMode.Open, FileAccess.Read, FileShare.None)

        resources.Add stream

    interface IDisposable with
        member _.Dispose() =
            for resource in Seq.rev resources do
                resource.Dispose()

            if Directory.Exists root then
                Directory.Delete(root, true)

let private words count =
    Seq.replicate count "word" |> String.concat " "

let private emptyDirectoryMap title =
    $"# {title}\n\n## Directory Map\n\nThis directory currently has no entries other than this README."

let private mermaid body = $"```mermaid\n{body}\n```"

let private coloredMermaid fence header color =
    $"{fence}mermaid\n{header}\n    A[Node]\n    classDef unsafe fill:{color},stroke:#000000,color:#FFFFFF\n    class A unsafe\n{fence}"

let private mermaidSample sample =
    let invalidClass definition =
        mermaid
            $"%%%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    {definition}\n    class A invalid"

    match sample with
    | "YAML front matter before an unsafe flowchart" ->
        mermaid
            "---\ntitle: Accessible diagram\n---\nflowchart LR\n    A[Node]\n    classDef unsafe fill:#FF0000,stroke:#000000,color:#FFFFFF\n    class A unsafe"
    | "no diagram declaration" -> mermaid "%% This block has no diagram declaration"
    | "accessible colored class" ->
        mermaid
            "%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef accessible fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px\n    class A accessible"
    | "style declaration color" ->
        mermaid
            "%% Accessible palette: blue #0173B2, orange #DE8F05, purple #CC78BC\nflowchart LR\n    A --> B\n    style A fill:#DE8F05,stroke:#000000,color:#000000"
    | "linkStyle declaration color" ->
        mermaid
            "%% Accessible palette: blue #0173B2, orange #DE8F05, purple #CC78BC\nflowchart LR\n    A --> B\n    linkStyle 0 stroke:#CC78BC,stroke-width:2px"
    | "initialization directive color" ->
        mermaid
            "%% Accessible palette: blue #0173B2, orange #DE8F05, purple #CC78BC\nflowchart LR\n    A --> B\n    %%{init: {'themeVariables': {'primaryColor': '#0173B2'}}}%%"
    | "named color" ->
        mermaid
            "%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef unsafe fill:red,stroke:#000000,color:#000000\n    class A unsafe"
    | "three-digit hex color" ->
        mermaid
            "%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef unsafe fill:#f00,stroke:#000000,color:#000000\n    class A unsafe"
    | "eight-digit hex color" ->
        mermaid
            "%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef unsafe fill:#DE8F05FF,stroke:#000000,color:#000000\n    class A unsafe"
    | "RGB function color" ->
        mermaid
            "%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef unsafe fill:rgb(222,143,5),stroke:#000000,color:#000000\n    class A unsafe"
    | "HSL function color" ->
        mermaid
            "%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef unsafe fill:hsl(38,96%,45%),stroke:#000000,color:#000000\n    class A unsafe"
    | "missing palette comment" ->
        mermaid
            "flowchart LR\n    A[Node]\n    classDef accessible fill:#DE8F05,stroke:#000000,color:#000000\n    class A accessible"
    | "duplicate palette comments" ->
        mermaid
            "%% Accessible palette: orange #DE8F05\n%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef accessible fill:#DE8F05,stroke:#000000,color:#000000\n    class A accessible"
    | "inaccurate palette comment" ->
        mermaid
            "%% Accessible palette: blue #0173B2\nflowchart LR\n    A[Node]\n    classDef accessible fill:#DE8F05,stroke:#000000,color:#000000\n    class A accessible"
    | "identical fill and stroke" -> invalidClass "classDef invalid fill:#000000,stroke:#000000,color:#FFFFFF"
    | "missing stroke" -> invalidClass "classDef invalid fill:#DE8F05,color:#000000"
    | "non-black node stroke" -> invalidClass "classDef invalid fill:#DE8F05,stroke:#0173B2,color:#000000"
    | "missing text color" -> invalidClass "classDef invalid fill:#DE8F05,stroke:#000000"
    | "unsupported text color" -> invalidClass "classDef invalid fill:#DE8F05,stroke:#000000,color:#0173B2"
    | "insufficient text contrast" -> invalidClass "classDef invalid fill:#DE8F05,stroke:#000000,color:#FFFFFF"
    | "accessible stroke-only class" ->
        mermaid
            "%% Accessible palette: purple #CC78BC\nflowchart LR\n    A e1@--> B\n    classDef accessibleEdge stroke:#CC78BC,stroke-width:2px,stroke-dasharray:5\\,5\n    class e1 accessibleEdge"
    | "text-only class" -> mermaid "flowchart LR\n    A --> B\n    classDef textOnly color:#000000"
    | "inaccessible stroke-only class" ->
        mermaid "flowchart LR\n    A --> B\n    classDef unsafeEdge stroke:#FF0000,stroke-width:2px"
    | _ -> failwithf "Unknown Mermaid sample '%s'." sample

let private expandInlineMarkdown (content: string) =
    content.Replace("{hash}", "#").Replace("{nul}", "\u0000")

let private tableRows (table: Table) =
    table.Rows
    |> Array.map (fun row ->
        if row.Length <> table.Header.Length then
            failwith "Every behaviour table row must have the same number of cells as its header."

        Array.zip table.Header row |> Map.ofArray)

let private cell name row =
    match Map.tryFind name row with
    | Some value -> value
    | None -> failwithf "Behaviour table is missing the '%s' column." name

let private violationKind =
    function
    | WordLimitExceeded _ -> "word limit exceeded"
    | MissingReadme _ -> "missing README"
    | MissingDirectoryMap _ -> "missing directory map"
    | MissingMapEntry _ -> "missing map entry"
    | InvalidMapEntry _ -> "invalid map entry"
    | MermaidAccessibilityViolation _ -> "Mermaid accessibility"

let private captureConsole action =
    let originalOut = Console.Out
    let originalError = Console.Error
    use output = new StringWriter()
    use error = new StringWriter()

    try
        Console.SetOut output
        Console.SetError error
        let result = action ()
        result, output.ToString(), error.ToString()
    finally
        Console.SetOut originalOut
        Console.SetError originalError

let private setCliResult (context: ScenarioContext) action =
    let result, output, error = captureConsole action
    context.ExitCode <- Some result
    context.StandardOutput <- output
    context.StandardError <- error

let private commandArguments validator =
    match validator with
    | "word-budget" -> [| "governance"; "word-budget"; "validate" |]
    | "directory-map" -> [| "governance"; "directory-map"; "validate" |]
    | "mermaid" -> [| "md"; "mermaid"; "validate" |]
    | _ -> failwithf "Unknown validator '%s'." validator

let private assertLinesStartWith prefix (text: string) =
    let lines = text.Split([| '\r'; '\n' |], StringSplitOptions.RemoveEmptyEntries)
    Assert.NotEmpty lines

    for line in lines do
        Assert.StartsWith(prefix, line)

let createScenarioContext () = new ScenarioContext()

let ``an empty repository`` (_: ScenarioContext) = ()

let ``the repository contains:`` (table: Table) (context: ScenarioContext) =
    for row in tableRows table do
        context.Write(cell "path" row, cell "content" row |> expandInlineMarkdown)

let ``file "(.*)" contains (\d+) words`` (path: string) (count: int) (context: ScenarioContext) =
    context.Write(path, words count)

let ``file "(.*)" contains this Markdown:`` (path: string) (content: string) (context: ScenarioContext) =
    context.Write(path, expandInlineMarkdown content)

let ``file "(.*)" has title "(.*)" and an empty directory map``
    (path: string)
    (title: string)
    (context: ScenarioContext)
    =
    context.Write(path, emptyDirectoryMap title)

let ``file "(.*)" has an empty "(.*)" directory map followed by (\d+) words``
    (path: string)
    (title: string)
    (count: int)
    (context: ScenarioContext)
    =
    context.Write(path, emptyDirectoryMap title + "\n\n" + words count)

let ``an unsafe "(.*)" Mermaid diagram exists at "(.*)" using (.*) fences``
    (header: string)
    (path: string)
    (fenceName: string)
    (context: ScenarioContext)
    =
    let fence =
        match fenceName with
        | "backtick" -> "```"
        | "tilde" -> "~~~"
        | _ -> failwithf "Unknown Mermaid fence '%s'." fenceName

    context.Write(path, coloredMermaid fence header "#FF0000")

let ``the repository contains Mermaid sample "(.*)" at "(.*)"``
    (sample: string)
    (path: string)
    (context: ScenarioContext)
    =
    context.Write(path, mermaidSample sample)

let ``each excluded directory contains an unsafe Mermaid diagram:``
    (directories: string array)
    (context: ScenarioContext)
    =
    for directory in directories do
        context.Write($"{directory}/diagram.md", coloredMermaid "```" "flowchart LR" "#FF0000")

let ``the governed files are exclusively locked`` (context: ScenarioContext) =
    context.Write("AGENTS.md", "# Instructions")
    context.Write("repo-governance/README.md", emptyDirectoryMap "Governance")
    context.Lock "AGENTS.md"
    context.Lock "repo-governance/README.md"

let ``Markdown text containing a heading marker, Hello, can't-stop, naïve, and 42`` (context: ScenarioContext) =
    context.Write("subject.md", "# Hello, can't-stop! naïve 42")

let ``I count the words in "(.*)"`` (path: string) (context: ScenarioContext) =
    File.ReadAllText(Path.Combine(context.Root, path))
    |> Governance.countWords
    |> Some
    |> fun count -> context.WordCount <- count

let ``I scan governed Markdown`` (context: ScenarioContext) =
    context.MarkdownFiles <- Governance.scanRepository context.Root
    context.Violations <- []

let ``I find word-limit violations`` (context: ScenarioContext) =
    context.MarkdownFiles <- Governance.scanRepository context.Root
    context.Violations <- context.MarkdownFiles |> Governance.findViolations |> List.map WordLimitExceeded

let ``I inspect the word budget`` (context: ScenarioContext) =
    let inspection = Governance.inspectWordBudget context.Root
    context.MarkdownFiles <- inspection.MarkdownFiles
    context.Violations <- inspection.Violations

let ``I inspect directory maps`` (context: ScenarioContext) =
    let inspection = Governance.inspectDirectoryMaps context.Root
    context.DirectoryCount <- Some inspection.DirectoryCount
    context.Violations <- inspection.Violations

let ``I inspect directory maps under the invalid "(.*)" location`` (location: string) (context: ScenarioContext) =
    let directory =
        match location with
        | "empty path" -> ""
        | "absolute repository root" -> context.Root
        | "outside repository" -> "../outside"
        | _ -> failwithf "Unknown invalid directory location '%s'." location

    try
        Governance.inspectDirectoryMapsAt context.Root directory |> ignore
        context.ExceptionRaised <- None
    with ex ->
        context.ExceptionRaised <- Some ex

let ``I inspect Mermaid accessibility`` (context: ScenarioContext) =
    let inspection = Governance.inspectMermaidAccessibility context.Root
    context.DiagramCount <- Some inspection.DiagramCount
    context.Violations <- inspection.Violations

let ``I run the "(.*)" validator`` (validator: string) (context: ScenarioContext) =
    let arguments =
        Array.append (commandArguments validator) [| "--root"; context.Root |]

    setCliResult context (fun () -> Program.main arguments)

let ``I run the directory-map validator for "(.*)"`` (directory: string) (context: ScenarioContext) =
    let arguments =
        [| "governance"
           "directory-map"
           "validate"
           "--directory"
           directory
           "--root"
           context.Root |]

    setCliResult context (fun () -> Program.main arguments)

let ``I invoke the CLI with "(.*)"`` (argumentText: string) (context: ScenarioContext) =
    let replaceArgument argument =
        match argument with
        | "{root}" -> context.Root
        | "{missing-root}" -> Path.Combine(context.Root, "missing")
        | value -> value

    let arguments =
        if String.IsNullOrEmpty argumentText then
            [||]
        else
            argumentText.Split('|') |> Array.map replaceArgument

    setCliResult context (fun () -> Program.main arguments)

let ``I invoke the CLI from the repository directory with "(.*)"`` (argumentText: string) (context: ScenarioContext) =
    let original = Directory.GetCurrentDirectory()

    try
        Directory.SetCurrentDirectory context.Root
        let arguments = argumentText.Split('|')
        setCliResult context (fun () -> Program.main arguments)
    finally
        Directory.SetCurrentDirectory original

let ``the word count is (\d+)`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(Some expected, context.WordCount)

let ``the scanned Markdown paths are:`` (expectedPaths: string array) (context: ScenarioContext) =
    Assert.Equal<string list>(expectedPaths |> Array.toList, context.MarkdownFiles |> List.map _.Path)

let ``no Markdown files are scanned`` (context: ScenarioContext) = Assert.Empty context.MarkdownFiles

let ``there are no violations`` (context: ScenarioContext) = Assert.Empty context.Violations

let ``there are (\d+) violations`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(expected, context.Violations.Length)

let ``all violations are "(.*)"`` (expectedKind: string) (context: ScenarioContext) =
    Assert.All(context.Violations, fun violation -> Assert.Equal(expectedKind, violationKind violation))

let ``the only violation is a (\d+)-word limit for "(.*)"``
    (expectedCount: int)
    (expectedPath: string)
    (context: ScenarioContext)
    =
    match Assert.Single context.Violations with
    | WordLimitExceeded file ->
        Assert.Equal(expectedPath, file.Path)
        Assert.Equal(expectedCount, file.WordCount)
    | violation -> failwithf "Expected WordLimitExceeded, got %A" violation

let ``the only violation is a missing directory map at "(.*)"`` (expectedPath: string) (context: ScenarioContext) =
    match Assert.Single context.Violations with
    | MissingDirectoryMap path -> Assert.Equal(expectedPath, path)
    | violation -> failwithf "Expected MissingDirectoryMap, got %A" violation

let ``the only violation is a missing README at "(.*)"`` (expectedPath: string) (context: ScenarioContext) =
    match Assert.Single context.Violations with
    | MissingReadme path -> Assert.Equal(expectedPath, path)
    | violation -> failwithf "Expected MissingReadme, got %A" violation

let ``the only violation is a missing map entry from "(.*)" to "(.*)"``
    (expectedReadme: string)
    (expectedSibling: string)
    (context: ScenarioContext)
    =
    match Assert.Single context.Violations with
    | MissingMapEntry(readme, sibling) ->
        Assert.Equal(expectedReadme, readme)
        Assert.Equal(expectedSibling, sibling)
    | violation -> failwithf "Expected MissingMapEntry, got %A" violation

let ``the only violation is an invalid map entry from "(.*)" to "(.*)"``
    (expectedReadme: string)
    (expectedTarget: string)
    (context: ScenarioContext)
    =
    match Assert.Single context.Violations with
    | InvalidMapEntry(readme, target) ->
        Assert.Equal(expectedReadme, readme)
        Assert.Equal(expectedTarget, target)
    | violation -> failwithf "Expected InvalidMapEntry, got %A" violation

let ``the violations include an overlong "(.*)" and its missing map entry for "(.*)"``
    (expectedReadme: string)
    (expectedSibling: string)
    (context: ScenarioContext)
    =
    let wordViolation =
        Governance.inspectWordBudget(context.Root).Violations |> Assert.Single

    let mapViolation =
        Governance.inspectDirectoryMaps(context.Root).Violations |> Assert.Single

    match wordViolation, mapViolation with
    | WordLimitExceeded file, MissingMapEntry(readme, sibling) ->
        Assert.Equal(expectedReadme, file.Path)
        Assert.True(file.WordCount > Governance.WordLimit)
        Assert.Equal(expectedReadme, readme)
        Assert.Equal(expectedSibling, sibling)
    | violations -> failwithf "Expected both violations, got %A" violations

let ``the only violation is a Mermaid accessibility issue at "(.*)"``
    (expectedPath: string)
    (context: ScenarioContext)
    =
    match Assert.Single context.Violations with
    | MermaidAccessibilityViolation issue -> Assert.Equal(expectedPath, issue.Path)
    | violation -> failwithf "Expected MermaidAccessibilityViolation, got %A" violation

let ``the formatted violation starts with "(.*)"`` (expectedPrefix: string) (context: ScenarioContext) =
    context.Violations
    |> Assert.Single
    |> Governance.formatViolation
    |> fun diagnostic -> Assert.StartsWith(expectedPrefix, diagnostic)

let ``(\d+) directories were inspected`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(Some expected, context.DirectoryCount)

let ``(\d+) Mermaid diagrams were inspected`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(Some expected, context.DiagramCount)

let ``an argument error is raised`` (context: ScenarioContext) =
    match context.ExceptionRaised with
    | Some(:? ArgumentException) -> ()
    | Some ex -> failwithf "Expected ArgumentException, got %s" (ex.GetType().FullName)
    | None -> failwith "Expected ArgumentException, but no exception was raised."

let ``the exit code is (\d+)`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(Some expected, context.ExitCode)

let ``stdout lines start with "(.*)"`` (prefix: string) (context: ScenarioContext) =
    assertLinesStartWith prefix context.StandardOutput

let ``stderr lines start with "(.*)"`` (prefix: string) (context: ScenarioContext) =
    assertLinesStartWith prefix context.StandardError

let ``stdout is empty`` (context: ScenarioContext) = Assert.Empty context.StandardOutput
