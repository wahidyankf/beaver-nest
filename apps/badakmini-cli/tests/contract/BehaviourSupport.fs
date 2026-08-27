module Badakmini.Cli.BehaviourSupport

open System
open System.Text.Json
open TickSpec
open global.Xunit
open Badakmini.Cli.BehaviourTests

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

let private assertLinesStartWith prefix (text: string) =
    let lines = text.Split([| '\r'; '\n' |], StringSplitOptions.RemoveEmptyEntries)
    Assert.NotEmpty lines

    for line in lines do
        Assert.StartsWith(prefix, line)

let createScenarioContext () =
    new ScenarioContext(BehaviourDriverFactory.create ())

let ``an empty repository`` (_: ScenarioContext) = ()

let ``the repository contains:`` (table: Table) (context: ScenarioContext) =
    for row in tableRows table do
        context.Driver.Write(cell "path" row, cell "content" row |> expandInlineMarkdown)

let ``file "(.*)" contains (\d+) words`` (path: string) (count: int) (context: ScenarioContext) =
    context.Driver.Write(path, words count)

let ``file "(.*)" contains this Markdown:`` (path: string) (content: string) (context: ScenarioContext) =
    context.Driver.Write(path, expandInlineMarkdown content)

let ``file "(.*)" has title "(.*)" and an empty directory map``
    (path: string)
    (title: string)
    (context: ScenarioContext)
    =
    context.Driver.Write(path, emptyDirectoryMap title)

let ``file "(.*)" has an empty "(.*)" directory map followed by (\d+) words``
    (path: string)
    (title: string)
    (count: int)
    (context: ScenarioContext)
    =
    context.Driver.Write(path, emptyDirectoryMap title + "\n\n" + words count)

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

    context.Driver.Write(path, coloredMermaid fence header "#FF0000")

let ``the repository contains Mermaid sample "(.*)" at "(.*)"``
    (sample: string)
    (path: string)
    (context: ScenarioContext)
    =
    context.Driver.Write(path, mermaidSample sample)

let ``each excluded directory contains an unsafe Mermaid diagram:``
    (directories: string array)
    (context: ScenarioContext)
    =
    for directory in directories do
        context.Driver.Write($"{directory}/diagram.md", coloredMermaid "```" "flowchart LR" "#FF0000")

let ``the governed files are exclusively locked`` (context: ScenarioContext) =
    context.Driver.Write("AGENTS.md", "# Instructions")
    context.Driver.Write("repo-governance/README.md", emptyDirectoryMap "Governance")
    context.Driver.Lock "AGENTS.md"
    context.Driver.Lock "repo-governance/README.md"

let ``Markdown text containing a heading marker, Hello, can't-stop, naïve, and 42`` (context: ScenarioContext) =
    context.Driver.Write("subject.md", "# Hello, can't-stop! naïve 42")

let ``I count the words in "(.*)"`` (path: string) (context: ScenarioContext) =
    context.WordCount <- context.Driver.CountWords path |> Some

let ``I scan governed Markdown`` (context: ScenarioContext) =
    context.MarkdownPaths <- context.Driver.ScanGovernedMarkdown()
    context.Violations <- []

let ``I find word-limit violations`` (context: ScenarioContext) =
    let paths, violations = context.Driver.FindWordLimitViolations()
    context.MarkdownPaths <- paths
    context.Violations <- violations

let ``I inspect the word budget`` (context: ScenarioContext) =
    let paths, violations = context.Driver.InspectWordBudget()
    context.MarkdownPaths <- paths
    context.Violations <- violations

let ``I inspect directory maps`` (context: ScenarioContext) =
    let count, violations = context.Driver.InspectDirectoryMaps()
    context.DirectoryCount <- Some count
    context.Violations <- violations

let ``I inspect directory maps under the invalid "(.*)" location`` (location: string) (context: ScenarioContext) =
    context.ArgumentErrorRaised <- context.Driver.InspectDirectoryMapsAtInvalidLocation location

let ``I inspect Mermaid accessibility`` (context: ScenarioContext) =
    let count, violations = context.Driver.InspectMermaidAccessibility()
    context.DiagramCount <- Some count
    context.Violations <- violations

let ``I run the "(.*)" validator`` (validator: string) (context: ScenarioContext) =
    context.CommandResult <- context.Driver.RunValidator validator |> Some

let ``I run the directory-map validator for "(.*)"`` (directory: string) (context: ScenarioContext) =
    context.CommandResult <- context.Driver.RunDirectoryMapValidator directory |> Some

let ``I invoke the CLI with "(.*)"`` (argumentText: string) (context: ScenarioContext) =
    let replaceArgument argument =
        match argument with
        | "{root}" -> context.Driver.Root
        | "{missing-root}" -> System.IO.Path.Combine(context.Driver.Root, "missing")
        | value -> value

    let arguments =
        if String.IsNullOrEmpty argumentText then
            [||]
        else
            argumentText.Split('|') |> Array.map replaceArgument

    context.CommandResult <- context.Driver.InvokeCli arguments |> Some

let ``I invoke the CLI from the repository directory with "(.*)"`` (argumentText: string) (context: ScenarioContext) =
    context.CommandResult <- context.Driver.InvokeCliFromRepository(argumentText.Split('|')) |> Some

let ``the word count is (\d+)`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(Some expected, context.WordCount)

let ``the scanned Markdown paths are:`` (expectedPaths: string array) (context: ScenarioContext) =
    Assert.Equal<string list>(expectedPaths |> Array.toList, context.MarkdownPaths)

let ``no Markdown files are scanned`` (context: ScenarioContext) = Assert.Empty context.MarkdownPaths

let ``there are no violations`` (context: ScenarioContext) = Assert.Empty context.Violations

let ``there are (\d+) violations`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(expected, context.Violations.Length)

let ``all violations are "(.*)"`` (expectedKind: string) (context: ScenarioContext) =
    Assert.All(context.Violations, fun violation -> Assert.Equal(expectedKind, violation.Kind))

let ``the only violation is a (\d+)-word limit for "(.*)"``
    (expectedCount: int)
    (expectedPath: string)
    (context: ScenarioContext)
    =
    let violation = Assert.Single context.Violations
    Assert.Equal("word limit exceeded", violation.Kind)
    Assert.Equal(expectedPath, violation.Path)
    Assert.Equal(Some expectedCount, violation.WordCount)

let ``the only violation is a missing directory map at "(.*)"`` (expectedPath: string) (context: ScenarioContext) =
    let violation = Assert.Single context.Violations
    Assert.Equal("missing directory map", violation.Kind)
    Assert.Equal(expectedPath, violation.Path)

let ``the only violation is a missing README at "(.*)"`` (expectedPath: string) (context: ScenarioContext) =
    let violation = Assert.Single context.Violations
    Assert.Equal("missing README", violation.Kind)
    Assert.Equal(expectedPath, violation.Path)

let ``the only violation is a missing map entry from "(.*)" to "(.*)"``
    (expectedReadme: string)
    (expectedSibling: string)
    (context: ScenarioContext)
    =
    let violation = Assert.Single context.Violations
    Assert.Equal("missing map entry", violation.Kind)
    Assert.Equal(expectedReadme, violation.Path)
    Assert.Equal(Some expectedSibling, violation.RelatedPath)

let ``the only violation is an invalid map entry from "(.*)" to "(.*)"``
    (expectedReadme: string)
    (expectedTarget: string)
    (context: ScenarioContext)
    =
    let violation = Assert.Single context.Violations
    Assert.Equal("invalid map entry", violation.Kind)
    Assert.Equal(expectedReadme, violation.Path)
    Assert.Equal(Some expectedTarget, violation.Target)

let ``the violations include an overlong "(.*)" and its missing map entry for "(.*)"``
    (expectedReadme: string)
    (expectedSibling: string)
    (context: ScenarioContext)
    =
    let _, wordViolations = context.Driver.InspectWordBudget()
    let _, mapViolations = context.Driver.InspectDirectoryMaps()
    let wordViolation = Assert.Single wordViolations
    let mapViolation = Assert.Single mapViolations
    Assert.Equal("word limit exceeded", wordViolation.Kind)
    Assert.Equal(expectedReadme, wordViolation.Path)
    Assert.True(wordViolation.WordCount |> Option.exists (fun count -> count > 750))
    Assert.Equal("missing map entry", mapViolation.Kind)
    Assert.Equal(expectedReadme, mapViolation.Path)
    Assert.Equal(Some expectedSibling, mapViolation.RelatedPath)

let ``the only violation is a Mermaid accessibility issue at "(.*)"``
    (expectedPath: string)
    (context: ScenarioContext)
    =
    let violation = Assert.Single context.Violations
    Assert.Equal("Mermaid accessibility", violation.Kind)
    Assert.Equal(expectedPath, violation.Path)

let ``the formatted violation starts with "(.*)"`` (expectedPrefix: string) (context: ScenarioContext) =
    context.Violations
    |> Assert.Single
    |> _.Diagnostic
    |> fun diagnostic -> Assert.StartsWith(expectedPrefix, diagnostic)

let ``(\d+) directories were inspected`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(Some expected, context.DirectoryCount)

let ``(\d+) Mermaid diagrams were inspected`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(Some expected, context.DiagramCount)

let ``an argument error is raised`` (context: ScenarioContext) =
    Assert.True(context.ArgumentErrorRaised, "Expected ArgumentException, but no argument error was observed.")

let ``the exit code is (\d+)`` (expected: int) (context: ScenarioContext) =
    Assert.Equal(expected, context.CommandResult.Value.ExitCode)

let ``stdout lines start with "(.*)"`` (prefix: string) (context: ScenarioContext) =
    assertLinesStartWith prefix context.CommandResult.Value.StandardOutput

let ``stderr lines start with "(.*)"`` (prefix: string) (context: ScenarioContext) =
    assertLinesStartWith prefix context.CommandResult.Value.StandardError

let ``stdout is empty`` (context: ScenarioContext) =
    Assert.Empty context.CommandResult.Value.StandardOutput

let ``stdout JSON property "(.*)" is (\d+)`` (property: string) (expected: int) (context: ScenarioContext) =
    use document = JsonDocument.Parse(context.CommandResult.Value.StandardOutput)
    Assert.Equal(expected, document.RootElement.GetProperty(property).GetInt32())

let ``the first stdout JSON violation kind is "(.*)"`` (expected: string) (context: ScenarioContext) =
    use document = JsonDocument.Parse(context.CommandResult.Value.StandardOutput)

    let violation =
        document.RootElement.GetProperty("violations").EnumerateArray() |> Seq.head

    Assert.Equal(expected, violation.GetProperty("kind").GetString())
