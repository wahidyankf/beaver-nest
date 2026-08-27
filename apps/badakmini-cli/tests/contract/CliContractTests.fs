namespace Badakmini.Cli.BehaviourTests

open System
open System.Text.Json
open global.Xunit
open Badakmini.Cli.BehaviourDriverFactory

type CliContractTests() =
    let invokeWithDriver arrange arguments =
        use driver = create ()
        arrange driver
        driver.InvokeCli arguments

    let noArrangement (_: IBehaviourDriver) = ()

    let jsonOutput result =
        JsonDocument.Parse(result.StandardOutput)

    let jsonError result =
        JsonDocument.Parse(result.StandardError)

    [<Fact>]
    member _.``JSON success responses expose every inspection shape``() =
        for arguments, property in
            [ [| "governance"; "word-budget"; "validate"; "--format"; "json" |], "markdownFiles"
              [| "governance"; "directory-map"; "validate"; "--format"; "json" |], "directoryCount"
              [| "md"; "links"; "validate"; "--format"; "json" |], "markdownFileCount"
              [| "md"; "mermaid"; "validate"; "--format"; "json" |], "diagramCount" ] do
            let result = invokeWithDriver noArrangement arguments
            Assert.Equal(0, result.ExitCode)
            use document = jsonOutput result
            let mutable value = Unchecked.defaultof<JsonElement>
            Assert.True(document.RootElement.TryGetProperty(property, &value), result.StandardOutput)

    [<Fact>]
    member _.``Mermaid validation can scope inspection to named files``() =
        let arrange (driver: IBehaviourDriver) =
            driver.Write("docs/selected.md", "```mermaid\nflowchart LR\nA --> B\n```")

            driver.Write("docs/also-selected.md", "```mermaid\nflowchart LR\nC --> D\n```")

            driver.Write(
                "docs/unselected.md",
                "```mermaid\nflowchart LR\nclassDef unsafe fill:#FF0000,stroke:#000000,color:#FFFFFF\n```"
            )

        let result =
            invokeWithDriver
                arrange
                [| "md"
                   "mermaid"
                   "validate"
                   "--file"
                   "docs/selected.md"
                   "--file"
                   "docs/also-selected.md" |]

        Assert.Equal(0, result.ExitCode)
        Assert.Contains("Checked 2 compatible Mermaid diagram(s)", result.StandardOutput)

    [<Theory>]
    [<InlineData("")>]
    [<InlineData("../outside.md")>]
    [<InlineData("/outside.md")>]
    [<InlineData("docs/missing.md")>]
    [<InlineData("docs/not-markdown.txt")>]
    member _.``Mermaid file selection rejects invalid locations``(path: string) =
        let arrange (driver: IBehaviourDriver) =
            if path = "docs/not-markdown.txt" then
                driver.Write(path, "not Markdown")

        let result =
            invokeWithDriver arrange [| "md"; "mermaid"; "validate"; "--file"; path; "--format"; "json" |]

        Assert.Equal(2, result.ExitCode)
        use error = jsonError result
        Assert.Equal("md mermaid validate", error.RootElement.GetProperty("command").GetString())

    [<Fact>]
    member _.``Mermaid validation reports a missing root as an operational error``() =
        let mutable missingRoot = ""

        let arrange (driver: IBehaviourDriver) =
            missingRoot <- System.IO.Path.Combine(driver.Root, "missing")

        let result =
            invokeWithDriver arrange [| "md"; "mermaid"; "validate"; "--root"; missingRoot; "--format"; "json" |]

        Assert.Equal(2, result.ExitCode)
        use error = jsonError result
        Assert.Equal("md mermaid validate", error.RootElement.GetProperty("command").GetString())

    [<Fact>]
    member _.``word-count exposes text JSON and operational errors``() =
        let arrange (driver: IBehaviourDriver) =
            driver.Write("subject.md", "one two three")

        let textResult =
            invokeWithDriver arrange [| "md"; "word-count"; "inspect"; "--file"; "subject.md" |]

        Assert.Equal(0, textResult.ExitCode)
        Assert.Contains("subject.md: 3 word(s).", textResult.StandardOutput)

        let jsonResult =
            invokeWithDriver arrange [| "md"; "word-count"; "inspect"; "--file"; "subject.md"; "--format"; "json" |]

        use document = jsonOutput jsonResult
        Assert.Equal(3, document.RootElement.GetProperty("wordCount").GetInt32())

        let missingResult =
            invokeWithDriver
                noArrangement
                [| "md"; "word-count"; "inspect"; "--file"; "missing.md"; "--format"; "json" |]

        Assert.Equal(2, missingResult.ExitCode)
        use error = jsonError missingResult
        Assert.Equal("md word-count inspect", error.RootElement.GetProperty("command").GetString())

    [<Fact>]
    member _.``JSON serializes every governance violation kind``() =
        let cases =
            [ (fun (driver: IBehaviourDriver) -> driver.Write("AGENTS.md", String.replicate 751 "word ")),
              [| "governance"; "word-budget"; "validate" |],
              "word-limit-exceeded"
              (fun driver -> driver.Write("repo-governance/README.md", "# Governance")),
              [| "governance"; "directory-map"; "validate" |],
              "missing-directory-map"
              (fun driver ->
                  driver.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Nested](nested)")

                  driver.Write("repo-governance/nested/rules.md", "# Rules")),
              [| "governance"; "directory-map"; "validate" |],
              "missing-readme"
              (fun driver ->
                  driver.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\nNo entries.")

                  driver.Write("repo-governance/rules.md", "# Rules")),
              [| "governance"; "directory-map"; "validate" |],
              "missing-map-entry"
              (fun driver ->
                  driver.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\n- [Old](old.md)")),
              [| "governance"; "directory-map"; "validate" |],
              "invalid-map-entry"
              (fun driver ->
                  driver.Write(
                      "docs/diagram.md",
                      "```mermaid\nflowchart LR\nclassDef unsafe fill:#FF0000,stroke:#000000,color:#FFFFFF\n```"
                  )),
              [| "md"; "mermaid"; "validate" |],
              "mermaid-accessibility"
              (fun driver -> driver.Write("docs/source.md", "[Missing](missing.md)")),
              [| "md"; "links"; "validate" |],
              "invalid-markdown-link" ]

        for arrange, command, expectedKind in cases do
            let result =
                invokeWithDriver arrange (Array.append command [| "--format"; "json" |])

            Assert.Equal(1, result.ExitCode)
            use document = jsonOutput result

            let violation =
                document.RootElement.GetProperty("violations").EnumerateArray() |> Seq.head

            Assert.Equal(expectedKind, violation.GetProperty("kind").GetString())

    [<Fact>]
    member _.``JSON operational failures remain command-specific``() =
        let arrange (driver: IBehaviourDriver) =
            driver.Write("AGENTS.md", "# Instructions")
            driver.Write("repo-governance/README.md", "# Governance\n\n## Directory Map\n\nNo entries.")
            driver.Lock "AGENTS.md"
            driver.Lock "repo-governance/README.md"

        for command, expected in
            [ [| "governance"; "word-budget"; "validate" |], "governance word-budget validate"
              [| "governance"; "directory-map"; "validate" |], "governance directory-map validate"
              [| "md"; "links"; "validate" |], "md links validate"
              [| "md"; "mermaid"; "validate" |], "md mermaid validate" ] do
            let result =
                invokeWithDriver arrange (Array.append command [| "--format"; "json" |])

            Assert.Equal(2, result.ExitCode)
            use document = jsonError result
            Assert.Equal(expected, document.RootElement.GetProperty("command").GetString())

    [<Theory>]
    [<InlineData("")>]
    [<InlineData("../outside.md")>]
    [<InlineData("/outside.md")>]
    member _.``word-count rejects invalid file locations``(path: string) =
        let result =
            invokeWithDriver noArrangement [| "md"; "word-count"; "inspect"; "--file"; path; "--format"; "json" |]

        Assert.Equal(2, result.ExitCode)

    [<Fact>]
    member _.``invalid output format is a usage failure``() =
        for arguments in
            [ [| "governance"; "word-budget"; "validate"; "--format"; "xml" |]
              [| "governance"; "directory-map"; "validate"; "--format"; "xml" |]
              [| "md"; "links"; "validate"; "--format"; "xml" |]
              [| "md"; "mermaid"; "validate"; "--format"; "xml" |]
              [| "md"; "word-count"; "inspect"; "--file"; "subject.md"; "--format"; "xml" |] ] do
            let result = invokeWithDriver noArrangement arguments
            Assert.Equal(2, result.ExitCode)
