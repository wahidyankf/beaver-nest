namespace Badakmini.Cli

open System
open System.CommandLine
open System.CommandLine.Parsing
open System.IO

module Cli =
    let private writeOutput category message =
        Console.Out.WriteLine($"[{category}] {message}")

    let private writeError category message =
        Console.Error.WriteLine($"[{category}] {message}")

    let private printViolations category violations =
        for violation in violations do
            Governance.formatViolation violation |> writeError category

    let private runWordBudget root =
        try
            let inspection = Governance.inspectWordBudget root

            if List.isEmpty inspection.Violations then
                sprintf
                    "Checked %d governed Markdown file(s); all are within the %d-word limit."
                    inspection.MarkdownFiles.Length
                    Governance.wordLimit
                |> writeOutput "word-budget"

                0
            else
                printViolations "word-budget" inspection.Violations

                sprintf "Found %d word-budget violation(s)." inspection.Violations.Length
                |> writeError "word-budget"

                1
        with ex ->
            writeError "word-budget" $"badakmini-cli: {ex.Message}"
            2

    let private runDirectoryMaps root =
        try
            let inspection = Governance.inspectDirectoryMaps root

            if List.isEmpty inspection.Violations then
                sprintf
                    "Checked %d governance directory map(s); all directory-map checks passed."
                    inspection.DirectoryCount
                |> writeOutput "directory-map"

                0
            else
                printViolations "directory-map" inspection.Violations

                sprintf "Found %d directory-map violation(s)." inspection.Violations.Length
                |> writeError "directory-map"

                1
        with ex ->
            writeError "directory-map" $"badakmini-cli: {ex.Message}"
            2

    let private runMermaidAccessibility root =
        try
            let inspection = Governance.inspectMermaidAccessibility root

            if List.isEmpty inspection.Violations then
                sprintf
                    "Checked %d compatible Mermaid diagram(s); all Mermaid accessibility checks passed."
                    inspection.DiagramCount
                |> writeOutput "mermaid"

                0
            else
                printViolations "mermaid" inspection.Violations

                sprintf "Found %d Mermaid accessibility violation(s)." inspection.Violations.Length
                |> writeError "mermaid"

                1
        with ex ->
            writeError "mermaid" $"badakmini-cli: {ex.Message}"
            2

    let private createLeaf name description (rootOption: Option<DirectoryInfo>) (action: string -> int) =
        let command = Command(name, description)

        command.SetAction(
            Func<ParseResult, int>(fun parseResult -> parseResult.GetRequiredValue(rootOption).FullName |> action)
        )

        command

    let createRootCommand () =
        let root = RootCommand("Validate repository governance and Markdown conventions.")

        let rootOption = Option<DirectoryInfo>("--root")
        rootOption.Description <- "Repository root to inspect. Defaults to the current directory."
        rootOption.Recursive <- true

        rootOption.DefaultValueFactory <-
            Func<ArgumentResult, DirectoryInfo>(fun _ -> DirectoryInfo(Directory.GetCurrentDirectory()))

        rootOption.AcceptExistingOnly() |> ignore
        root.Options.Add rootOption

        let governance = Command("governance", "Validate repository governance structures.")
        let wordBudget = Command("word-budget", "Validate governed Markdown word limits.")

        wordBudget.Subcommands.Add(
            createLeaf
                "validate"
                "Validate governed Markdown against the repository word limit."
                rootOption
                runWordBudget
        )

        let directoryMap =
            Command("directory-map", "Validate governance README directory maps.")

        directoryMap.Subcommands.Add(
            createLeaf
                "validate"
                "Validate README presence, sibling coverage, and directory-map links."
                rootOption
                runDirectoryMaps
        )

        governance.Subcommands.Add wordBudget
        governance.Subcommands.Add directoryMap

        let markdown = Command("md", "Validate repository-owned Markdown.")
        let mermaid = Command("mermaid", "Validate compatible Mermaid diagrams.")

        mermaid.Subcommands.Add(
            createLeaf
                "validate"
                "Validate accessible colors in compatible Mermaid diagrams."
                rootOption
                runMermaidAccessibility
        )

        markdown.Subcommands.Add mermaid
        root.Subcommands.Add governance
        root.Subcommands.Add markdown
        root

    let invoke (args: string array) =
        let parseResult = createRootCommand().Parse(args)
        let invocationConfiguration = InvocationConfiguration()
        let exitCode = parseResult.Invoke(invocationConfiguration)

        if parseResult.Errors.Count > 0 then 2 else exitCode
