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
    Program.main [| repository.Root |]

[<Fact>]
let ``countWords counts text rather than Markdown punctuation`` () =
    let content = "# Hello, can't-stop! naïve 42"

    Assert.Equal(4, Governance.countWords content)

[<Fact>]
let ``scanRepository includes AGENTS and nested governance Markdown only`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", "agents rules")
    repository.Write("repo-governance/nested/RULES.MD", "nested rules")
    repository.Write("repo-governance/notes.txt", "not Markdown")
    repository.Write("README.md", "outside governance")

    let files = Governance.scanRepository repository.Root

    Assert.Equal<string list>([ "AGENTS.md"; "repo-governance/nested/RULES.MD" ], files |> List.map _.Path)

[<Fact>]
let ``findViolations allows 500 words and rejects 501`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words Governance.wordLimit)
    repository.Write("repo-governance/too-long.md", words (Governance.wordLimit + 1))

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

        Assert.Equal(1, Program.main [| repository.Root |])

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

        Assert.Equal(0, Program.main [| repository.Root |])

[<Fact>]
let ``CLI extracts tilde-fenced Mermaid diagrams`` () =
    use repository = new TemporaryRepository()

    repository.Write("plans/diagram.md", coloredMermaid "~~~" "flowchart LR" "#FF0000")

    Assert.Equal(1, Program.main [| repository.Root |])

[<Fact>]
let ``CLI finds the diagram type after Mermaid YAML front matter`` () =
    let content =
        mermaid
            "---\ntitle: Accessible diagram\n---\nflowchart LR\n    A[Node]\n    classDef unsafe fill:#FF0000,stroke:#000000,color:#FFFFFF\n    class A unsafe"

    Assert.Equal(1, cliResult content)

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

    Assert.Equal(0, Program.main [| repository.Root |])

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
let ``Mermaid diagnostics include the Markdown path and source line`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "docs/diagram.md",
        "# Diagram\n\n```mermaid\nflowchart LR\n    A[Node]\n    classDef unsafe fill:#FF0000,stroke:#000000,color:#FFFFFF\n```"
    )

    let violation =
        Governance.inspectRepository(repository.Root).Violations
        |> fun violations -> Assert.Single violations
        |> Governance.formatViolation

    Assert.StartsWith("docs/diagram.md:6:", violation)

[<Fact>]
let ``inspectRepository accepts complete direct-sibling maps`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Nested](nested/README.md)\n- [Rules](rules.md)"
    )

    repository.Write("repo-governance/nested/README.md", emptyDirectoryMap "Nested")

    repository.Write("repo-governance/rules.md", "# Rules")

    let inspection = Governance.inspectRepository repository.Root

    Assert.Equal(2, inspection.GovernanceDirectoryCount)
    Assert.Empty(inspection.Violations)

[<Fact>]
let ``inspectRepository requires README in every governance directory`` () =
    use repository = new TemporaryRepository()

    repository.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Nested](nested)")

    repository.Write("repo-governance/nested/rules.md", "# Rules")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingReadme path -> Assert.Equal("repo-governance/nested", path)
    | _ -> failwithf "Expected MissingReadme, got %A" violation

[<Fact>]
let ``inspectRepository requires a Directory Map section`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", "# Governance")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingDirectoryMap path -> Assert.Equal("repo-governance/README.md", path)
    | _ -> failwithf "Expected MissingDirectoryMap, got %A" violation

[<Fact>]
let ``inspectRepository rejects an omitted sibling`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", emptyDirectoryMap "Governance")
    repository.Write("repo-governance/rules.md", "# Rules")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingMapEntry(readmePath, siblingPath) ->
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("repo-governance/rules.md", siblingPath)
    | _ -> failwithf "Expected MissingMapEntry, got %A" violation

[<Fact>]
let ``inspectRepository reports an overlong README and its omitted sibling`` () =
    use repository = new TemporaryRepository()

    let readme =
        emptyDirectoryMap "Governance" + "\n\n" + words (Governance.wordLimit + 1)

    repository.Write("repo-governance/README.md", readme)

    repository.Write("repo-governance/rules.md", "# Rules")

    match Governance.inspectRepository(repository.Root).Violations with
    | [ WordLimitExceeded file; MissingMapEntry(readmePath, siblingPath) ] ->
        Assert.Equal("repo-governance/README.md", file.Path)
        Assert.True(file.WordCount > Governance.wordLimit)
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("repo-governance/rules.md", siblingPath)
    | violations -> failwithf "Expected both violations, got %A" violations

[<Fact>]
let ``inspectRepository rejects a nonexistent map entry`` () =
    use repository = new TemporaryRepository()

    repository.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Old rules](old-rules.md)")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | InvalidMapEntry(readmePath, target) ->
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("old-rules.md", target)
    | _ -> failwithf "Expected InvalidMapEntry, got %A" violation

[<Fact>]
let ``inspectRepository rejects an existing non-sibling map entry`` () =
    use repository = new TemporaryRepository()

    repository.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Nested](nested/README.md)")

    repository.Write("repo-governance/nested/README.md", "# Nested\n\n## Directory Map\n\n- [Parent](../README.md)")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | InvalidMapEntry(readmePath, target) ->
        Assert.Equal("repo-governance/nested/README.md", readmePath)
        Assert.Equal("../README.md", target)
    | _ -> failwithf "Expected InvalidMapEntry, got %A" violation

[<Fact>]
let ``CLI returns failure when a governed file exceeds the limit`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.wordLimit + 1))

    Assert.Equal(1, Program.main [| repository.Root |])

[<Fact>]
let ``CLI returns failure when governance navigation is invalid`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", "# Governance")

    Assert.Equal(1, Program.main [| repository.Root |])
