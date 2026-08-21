module Badakmini.Cli.Tests

open System
open System.IO
open Xunit
open Badakmini.Cli

type private TemporaryRepository() =
    let root = Path.Combine(Path.GetTempPath(), $"badakmini-cli-{Guid.NewGuid():N}")

    do Directory.CreateDirectory(root) |> ignore

    member _.Root = root

    member _.Write(relativePath: string, content: string) =
        let path = Path.Combine(root, relativePath)
        Directory.CreateDirectory(Path.GetDirectoryName path) |> ignore
        File.WriteAllText(path, content)

    interface IDisposable with
        member _.Dispose() = Directory.Delete(root, true)

let private words count =
    Seq.replicate count "word" |> String.concat " "

let private emptyDirectoryMap title =
    $"# {title}\n\n## Directory Map\n\nThis directory currently has no entries other than this README."

let private coloredMermaid fence header color =
    $"{fence}mermaid\n{header}\n    A[Node]\n    classDef unsafe fill:{color},stroke:#000000,color:#FFFFFF\n    class A unsafe\n{fence}"

let private mermaid body = $"```mermaid\n{body}\n```"

let private cliResult content =
    use repository = new TemporaryRepository()
    repository.Write("docs/diagram.md", content)

    Program.main [| "md"; "mermaid"; "validate"; "--root"; repository.Root |]

let private runCli root command =
    Program.main (Array.append command [| "--root"; root |])

let private runWordBudget root =
    runCli root [| "governance"; "word-budget"; "validate" |]

let private runDirectoryMap root =
    runCli root [| "governance"; "directory-map"; "validate" |]

let private runDirectoryMapFor directory root =
    runCli root [| "governance"; "directory-map"; "validate"; "--directory"; directory |]

let private runMermaid root =
    runCli root [| "md"; "mermaid"; "validate" |]

let private workingDirectoryLock = obj ()

let private inWorkingDirectory path action =
    lock workingDirectoryLock (fun () ->
        let original = Directory.GetCurrentDirectory()

        try
            Directory.SetCurrentDirectory path
            action ()
        finally
            Directory.SetCurrentDirectory original)

let private captureConsole action =
    lock workingDirectoryLock (fun () ->
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
            Console.SetError originalError)

let private assertLinesStartWith prefix (text: string) =
    let lines = text.Split([| '\r'; '\n' |], StringSplitOptions.RemoveEmptyEntries)

    Assert.NotEmpty lines

    for line in lines do
        Assert.StartsWith(prefix, line)

[<Fact>]
let ``countWords counts text rather than Markdown punctuation`` () =
    let content = "# Hello, can't-stop! naïve 42"

    Assert.Equal(4, Governance.countWords content)

[<Fact>]
let ``scanRepository excludes docs and includes governed Markdown only`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", "agents rules")
    repository.Write("repo-governance/nested/RULES.MD", "nested rules")
    repository.Write("repo-governance/notes.txt", "not Markdown")
    repository.Write("docs/long-form.md", words (Governance.WordLimit + 1))
    repository.Write("README.md", "outside governance")

    let files = Governance.scanRepository repository.Root

    Assert.Equal<string list>([ "AGENTS.md"; "repo-governance/nested/RULES.MD" ], files |> List.map _.Path)

[<Fact>]
let ``findViolations allows 500 words and rejects 501`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words Governance.WordLimit)
    repository.Write("repo-governance/too-long.md", words (Governance.WordLimit + 1))

    let violations =
        Governance.scanRepository repository.Root |> Governance.findViolations

    let violation = Assert.Single violations
    Assert.Equal("repo-governance/too-long.md", violation.Path)
    Assert.Equal(501, violation.WordCount)

[<Fact>]
let ``scanRepository handles missing optional paths`` () =
    use repository = new TemporaryRepository()

    Assert.Empty(Governance.scanRepository repository.Root)

[<Fact>]
let ``inspectWordBudget reports only governed Markdown word-limit violations`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.WordLimit + 1))
    repository.Write("repo-governance/README.md", "# Governance")
    repository.Write("docs/diagram.md", coloredMermaid "```" "flowchart LR" "#FF0000")

    let inspection = Governance.inspectWordBudget repository.Root
    let violation = Assert.Single inspection.Violations

    Assert.Equal<string list>([ "AGENTS.md"; "repo-governance/README.md" ], inspection.MarkdownFiles |> List.map _.Path)

    match violation with
    | WordLimitExceeded file -> Assert.Equal("AGENTS.md", file.Path)
    | _ -> failwithf "Expected WordLimitExceeded, got %A" violation

[<Fact>]
let ``inspectDirectoryMaps reports only governance directory-map violations`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.WordLimit + 1))
    repository.Write("repo-governance/README.md", "# Governance")
    repository.Write("docs/diagram.md", coloredMermaid "```" "flowchart LR" "#FF0000")

    let inspection = Governance.inspectDirectoryMaps repository.Root
    let violation = Assert.Single inspection.Violations

    Assert.Equal(1, inspection.DirectoryCount)

    match violation with
    | MissingDirectoryMap path -> Assert.Equal("repo-governance/README.md", path)
    | _ -> failwithf "Expected MissingDirectoryMap, got %A" violation

[<Fact>]
let ``inspectMermaidAccessibility reports only compatible Mermaid violations`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.WordLimit + 1))
    repository.Write("repo-governance/README.md", "# Governance")
    repository.Write("docs/diagram.md", coloredMermaid "```" "flowchart LR" "#FF0000")

    let inspection = Governance.inspectMermaidAccessibility repository.Root
    let violation = Assert.Single inspection.Violations

    Assert.Equal(1, inspection.DiagramCount)

    match violation with
    | MermaidAccessibilityViolation issue -> Assert.Equal("docs/diagram.md", issue.Path)
    | _ -> failwithf "Expected MermaidAccessibilityViolation, got %A" violation

[<Fact>]
let ``CLI accepts every canonical nested command path`` () =
    use repository = new TemporaryRepository()

    Assert.Equal(0, runWordBudget repository.Root)
    Assert.Equal(0, runDirectoryMap repository.Root)
    Assert.Equal(0, runMermaid repository.Root)

[<Fact>]
let ``CLI commands isolate word-budget validation`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.WordLimit + 1))

    Assert.Equal(1, runWordBudget repository.Root)
    Assert.Equal(0, runDirectoryMap repository.Root)
    Assert.Equal(0, runMermaid repository.Root)

[<Fact>]
let ``CLI commands isolate directory-map validation`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", "# Governance")

    Assert.Equal(0, runWordBudget repository.Root)
    Assert.Equal(1, runDirectoryMap repository.Root)
    Assert.Equal(0, runMermaid repository.Root)

[<Fact>]
let ``CLI directory-map accepts a complete selected docs tree`` () =
    use repository = new TemporaryRepository()

    repository.Write("docs/README.md", "# Docs\n\n## Directory Map\n\n- [Nested](nested/README.md)")
    repository.Write("docs/nested/README.md", emptyDirectoryMap "Nested")

    Assert.Equal(0, runDirectoryMapFor "docs" repository.Root)

[<Fact>]
let ``CLI directory-map requires README in every selected docs directory`` () =
    use repository = new TemporaryRepository()

    repository.Write("docs/README.md", "# Docs\n\n## Directory Map\n\n- [Nested](nested/README.md)")
    repository.Write("docs/nested/guide.md", "# Guide")

    Assert.Equal(1, runDirectoryMapFor "docs" repository.Root)

[<Fact>]
let ``CLI directory-map rejects an omitted sibling in selected docs`` () =
    use repository = new TemporaryRepository()
    repository.Write("docs/README.md", emptyDirectoryMap "Docs")
    repository.Write("docs/guide.md", "# Guide")

    Assert.Equal(1, runDirectoryMapFor "docs" repository.Root)

[<Fact>]
let ``CLI commands isolate Mermaid accessibility validation`` () =
    use repository = new TemporaryRepository()
    repository.Write("docs/diagram.md", coloredMermaid "```" "flowchart LR" "#FF0000")

    Assert.Equal(0, runWordBudget repository.Root)
    Assert.Equal(0, runDirectoryMap repository.Root)
    Assert.Equal(1, runMermaid repository.Root)

[<Fact>]
let ``CLI root option defaults to the current directory`` () =
    use repository = new TemporaryRepository()

    let exitCode =
        inWorkingDirectory repository.Root (fun () -> Program.main [| "governance"; "word-budget"; "validate" |])

    Assert.Equal(0, exitCode)

[<Fact>]
let ``CLI root option is accepted before and after nested commands`` () =
    use repository = new TemporaryRepository()

    let before =
        Program.main [| "--root"; repository.Root; "governance"; "word-budget"; "validate" |]

    let after = runWordBudget repository.Root

    Assert.Equal(0, before)
    Assert.Equal(0, after)

[<Fact>]
let ``CLI leaf output carries an atomic command-category prefix`` () =
    use repository = new TemporaryRepository()

    let wordExit, wordOutput, _ =
        captureConsole (fun () -> runWordBudget repository.Root)

    let mapExit, mapOutput, _ =
        captureConsole (fun () -> runDirectoryMap repository.Root)

    let mermaidExit, mermaidOutput, _ =
        captureConsole (fun () -> runMermaid repository.Root)

    Assert.Equal(0, wordExit)
    Assert.Equal(0, mapExit)
    Assert.Equal(0, mermaidExit)
    assertLinesStartWith "[word-budget] " wordOutput
    assertLinesStartWith "[directory-map] " mapOutput
    assertLinesStartWith "[mermaid] " mermaidOutput

    repository.Write("AGENTS.md", words (Governance.WordLimit + 1))

    let failureExit, _, failureError =
        captureConsole (fun () -> runWordBudget repository.Root)

    Assert.Equal(1, failureExit)
    assertLinesStartWith "[word-budget] " failureError

[<Fact>]
let ``CLI help and version requests succeed`` () =
    let invocations =
        [ [| "--help" |]
          [| "--version" |]
          [| "governance"; "--help" |]
          [| "governance"; "word-budget"; "--help" |]
          [| "governance"; "word-budget"; "validate"; "--help" |]
          [| "md"; "--help" |]
          [| "md"; "mermaid"; "--help" |]
          [| "md"; "mermaid"; "validate"; "--help" |] ]

    for invocation in invocations do
        Assert.Equal(0, Program.main invocation)

[<Fact>]
let ``CLI rejects legacy incomplete unknown extra and missing-root invocations`` () =
    use repository = new TemporaryRepository()

    let missingRoot = Path.Combine(repository.Root, "missing")

    let invocations =
        [ [| repository.Root |]
          [| "governance" |]
          [| "governance"; "word-budget" |]
          [| "md"; "mermaid" |]
          [| "unknown" |]
          [| "governance"; "word-budget"; "validate"; "extra" |]
          [| "governance"; "word-budget"; "validate"; "--root"; missingRoot |] ]

    for invocation in invocations do
        Assert.Equal(2, Program.main invocation)

[<Fact>]
let ``CLI checks classDef colors for compatible Mermaid diagram types`` () =
    let headers =
        [ "flowchart LR"
          "graph TD"
          "classDiagram"
          "stateDiagram"
          "stateDiagram-v2"
          "erDiagram"
          "requirementDiagram"
          "block" ]

    for header in headers do
        use repository = new TemporaryRepository()

        repository.Write($"docs/{header.Replace(' ', '-').Replace('/', '-')}.md", coloredMermaid "```" header "#FF0000")

        Assert.Equal(1, runMermaid repository.Root)

[<Fact>]
let ``CLI skips Mermaid types without compatible classDef color semantics`` () =
    let headers =
        [ "sequenceDiagram"
          "mindmap"
          "timeline"
          "kanban"
          "architecture-beta"
          "treeView"
          "gantt"
          "pie"
          "quadrantChart"
          "treemap-beta"
          "swimlane-beta"
          "futureDiagram" ]

    for header in headers do
        use repository = new TemporaryRepository()
        repository.Write("docs/diagram.md", coloredMermaid "```" header "#FF0000")

        Assert.Equal(0, runMermaid repository.Root)

[<Fact>]
let ``CLI extracts tilde-fenced Mermaid diagrams`` () =
    use repository = new TemporaryRepository()

    repository.Write("plans/diagram.md", coloredMermaid "~~~" "flowchart LR" "#FF0000")

    Assert.Equal(1, runMermaid repository.Root)

[<Fact>]
let ``CLI finds the diagram type after Mermaid YAML front matter`` () =
    let content =
        mermaid
            "---\ntitle: Accessible diagram\n---\nflowchart LR\n    A[Node]\n    classDef unsafe fill:#FF0000,stroke:#000000,color:#FFFFFF\n    class A unsafe"

    Assert.Equal(1, cliResult content)

[<Fact>]
let ``CLI skips Mermaid blocks without a diagram type`` () =
    Assert.Equal(0, cliResult (mermaid "%% This block has no diagram declaration"))

[<Fact>]
let ``CLI ignores Mermaid diagrams in generated and dependency directories`` () =
    let excludedDirectories =
        [ ".git"
          ".nx"
          "node_modules"
          "bin"
          "obj"
          "_build"
          "deps"
          "coverage"
          "playwright-report"
          "test-results" ]

    use repository = new TemporaryRepository()

    for directory in excludedDirectories do
        repository.Write($"{directory}/diagram.md", coloredMermaid "```" "flowchart LR" "#FF0000")

    Assert.Equal(0, runMermaid repository.Root)

[<Fact>]
let ``CLI accepts an accessible colored Mermaid class`` () =
    let content =
        mermaid
            "%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef accessible fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px\n    class A accessible"

    Assert.Equal(0, cliResult content)

[<Fact>]
let ``CLI rejects colors outside classDef declarations`` () =
    let declarations =
        [ "style A fill:#DE8F05,stroke:#000000,color:#000000"
          "linkStyle 0 stroke:#CC78BC,stroke-width:2px"
          "%%{init: {'themeVariables': {'primaryColor': '#0173B2'}}}%%" ]

    for declaration in declarations do
        let content =
            mermaid
                $"%%%% Accessible palette: blue #0173B2, orange #DE8F05, purple #CC78BC\nflowchart LR\n    A --> B\n    {declaration}"

        Assert.True(cliResult content = 1, $"Expected rejection:\n{content}")

[<Fact>]
let ``CLI rejects unsupported Mermaid color formats`` () =
    let colors = [ "red"; "#f00"; "#DE8F05FF"; "rgb(222,143,5)"; "hsl(38,96%,45%)" ]

    for color in colors do
        let content =
            mermaid
                $"%%%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    classDef unsafe fill:{color},stroke:#000000,color:#000000\n    class A unsafe"

        Assert.True(cliResult content = 1, $"Expected rejection:\n{content}")

[<Fact>]
let ``CLI requires exactly one accurate palette comment for colored diagrams`` () =
    let classDefinition =
        "flowchart LR\n    A[Node]\n    classDef accessible fill:#DE8F05,stroke:#000000,color:#000000\n    class A accessible"

    let invalidComments =
        [ ""
          "%% Accessible palette: orange #DE8F05\n%% Accessible palette: orange #DE8F05"
          "%% Accessible palette: blue #0173B2" ]

    for comment in invalidComments do
        let content =
            if String.IsNullOrEmpty comment then
                mermaid classDefinition
            else
                mermaid $"{comment}\n{classDefinition}"

        Assert.True(cliResult content = 1, $"Expected rejection: {comment}")

[<Fact>]
let ``CLI enforces node color roles and normal-text contrast`` () =
    let invalidDefinitions =
        [ "classDef invalid fill:#000000,stroke:#000000,color:#FFFFFF"
          "classDef invalid fill:#DE8F05,color:#000000"
          "classDef invalid fill:#DE8F05,stroke:#0173B2,color:#000000"
          "classDef invalid fill:#DE8F05,stroke:#000000"
          "classDef invalid fill:#DE8F05,stroke:#000000,color:#0173B2"
          "classDef invalid fill:#DE8F05,stroke:#000000,color:#FFFFFF" ]

    for definition in invalidDefinitions do
        let content =
            mermaid
                $"%%%% Accessible palette: orange #DE8F05\nflowchart LR\n    A[Node]\n    {definition}\n    class A invalid"

        Assert.True(cliResult content = 1, $"Expected rejection:\n{content}")

[<Fact>]
let ``CLI accepts accessible stroke-only classes`` () =
    let content =
        mermaid
            "%% Accessible palette: purple #CC78BC\nflowchart LR\n    A e1@--> B\n    classDef accessibleEdge stroke:#CC78BC,stroke-width:2px,stroke-dasharray:5\\,5\n    class e1 accessibleEdge"

    Assert.Equal(0, cliResult content)

[<Fact>]
let ``CLI rejects text-only and inaccessible stroke-only classes`` () =
    let invalidDefinitions =
        [ "classDef textOnly color:#000000"
          "classDef unsafeEdge stroke:#FF0000,stroke-width:2px" ]

    for definition in invalidDefinitions do
        let content = mermaid $"flowchart LR\n    A --> B\n    {definition}"

        Assert.True(cliResult content = 1, $"Expected rejection:\n{content}")

[<Fact>]
let ``Mermaid diagnostics include the Markdown path and source line`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "docs/diagram.md",
        "# Diagram\n\n```mermaid\nflowchart LR\n    A[Node]\n    classDef unsafe fill:#FF0000,stroke:#000000,color:#FFFFFF\n```"
    )

    let violation =
        Governance.inspectMermaidAccessibility(repository.Root).Violations
        |> Assert.Single
        |> Governance.formatViolation

    Assert.StartsWith("docs/diagram.md:6:", violation)

[<Fact>]
let ``inspectDirectoryMaps accepts complete direct-sibling maps`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Nested](nested/README.md)\n- [Rules](rules.md)"
    )

    repository.Write("repo-governance/nested/README.md", emptyDirectoryMap "Nested")

    repository.Write("repo-governance/rules.md", "# Rules")

    let inspection = Governance.inspectDirectoryMaps repository.Root

    Assert.Equal(2, inspection.DirectoryCount)
    Assert.Empty(inspection.Violations)

[<Fact>]
let ``inspectDirectoryMaps requires a relative directory within the repository`` () =
    use repository = new TemporaryRepository()

    let invalidDirectories = [ ""; repository.Root; "../outside" ]

    for directory in invalidDirectories do
        Assert.Throws<ArgumentException>(fun () ->
            Governance.inspectDirectoryMapsAt repository.Root directory |> ignore)
        |> ignore

[<Fact>]
let ``inspectDirectoryMaps resolves sibling links before query and fragment suffixes`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Rules](rules.md?raw=1#details)"
    )

    repository.Write("repo-governance/rules.md", "# Rules")

    Assert.Empty(Governance.inspectDirectoryMaps(repository.Root).Violations)

[<Fact>]
let ``inspectDirectoryMaps rejects absolute URL and malformed sibling links`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Absolute](/rules.md)\n- [URL](https://example.com/rules.md)\n- [Malformed](bad\u0000path.md)"
    )

    let violations = Governance.inspectDirectoryMaps(repository.Root).Violations

    Assert.Equal(3, violations.Length)

    for violation in violations do
        match violation with
        | InvalidMapEntry _ -> ()
        | _ -> failwithf "Expected InvalidMapEntry, got %A" violation

[<Fact>]
let ``inspectDirectoryMaps requires README in every governance directory`` () =
    use repository = new TemporaryRepository()

    repository.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Nested](nested)")

    repository.Write("repo-governance/nested/rules.md", "# Rules")

    let violation =
        Governance.inspectDirectoryMaps repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingReadme path -> Assert.Equal("repo-governance/nested", path)
    | _ -> failwithf "Expected MissingReadme, got %A" violation

[<Fact>]
let ``inspectDirectoryMaps requires a Directory Map section`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", "# Governance")

    let violation =
        Governance.inspectDirectoryMaps repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingDirectoryMap path -> Assert.Equal("repo-governance/README.md", path)
    | _ -> failwithf "Expected root README MissingDirectoryMap, got %A" violation

[<Fact>]
let ``inspectDirectoryMaps rejects an omitted sibling`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", emptyDirectoryMap "Governance")
    repository.Write("repo-governance/rules.md", "# Rules")

    let violation =
        Governance.inspectDirectoryMaps repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingMapEntry(readmePath, siblingPath) ->
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("repo-governance/rules.md", siblingPath)
    | _ -> failwithf "Expected MissingMapEntry, got %A" violation

[<Fact>]
let ``independent inspections report an overlong README and its omitted sibling`` () =
    use repository = new TemporaryRepository()

    let readme =
        emptyDirectoryMap "Governance" + "\n\n" + words (Governance.WordLimit + 1)

    repository.Write("repo-governance/README.md", readme)

    repository.Write("repo-governance/rules.md", "# Rules")

    let wordViolation =
        Governance.inspectWordBudget(repository.Root).Violations |> Assert.Single

    let directoryMapViolation =
        Governance.inspectDirectoryMaps(repository.Root).Violations |> Assert.Single

    match wordViolation, directoryMapViolation with
    | WordLimitExceeded file, MissingMapEntry(readmePath, siblingPath) ->
        Assert.Equal("repo-governance/README.md", file.Path)
        Assert.True(file.WordCount > Governance.WordLimit)
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("repo-governance/rules.md", siblingPath)
    | violations -> failwithf "Expected both violations, got %A" violations

[<Fact>]
let ``inspectDirectoryMaps rejects a nonexistent map entry`` () =
    use repository = new TemporaryRepository()

    repository.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Old rules](old-rules.md)")

    let violation =
        Governance.inspectDirectoryMaps repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | InvalidMapEntry(readmePath, target) ->
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("old-rules.md", target)
    | _ -> failwithf "Expected nonexistent-target InvalidMapEntry, got %A" violation

[<Fact>]
let ``inspectDirectoryMaps rejects an existing non-sibling map entry`` () =
    use repository = new TemporaryRepository()

    repository.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Nested](nested/README.md)")

    repository.Write("repo-governance/nested/README.md", "# Nested\n\n## Directory Map\n\n- [Parent](../README.md)")

    let violation =
        Governance.inspectDirectoryMaps repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | InvalidMapEntry(readmePath, target) ->
        Assert.Equal("repo-governance/nested/README.md", readmePath)
        Assert.Equal("../README.md", target)
    | _ -> failwithf "Expected non-sibling InvalidMapEntry, got %A" violation

[<Fact>]
let ``CLI returns failure when a governed file exceeds the limit`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.WordLimit + 1))

    Assert.Equal(1, runWordBudget repository.Root)

[<Fact>]
let ``CLI returns failure when governance navigation is invalid`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", "# Governance")

    Assert.Equal(1, runDirectoryMap repository.Root)
